import Foundation

struct ActivitySnapshot {
    var agentCount: Int          // number of detected agent sessions (root processes)
    var activeAgentCount: Int    // how many of those are working right now
    var isActive: Bool           // at least one agent is working right now
    var netBytesPerSec: Double   // throughput of the busiest agent
    var cpuPercent: Double       // CPU% of the busiest agent's subtree

    static let empty = ActivitySnapshot(agentCount: 0, activeAgentCount: 0,
                                        isActive: false, netBytesPerSec: 0, cpuPercent: 0)
}

/// Polls the system to decide whether any watched AI-agent process is actively
/// working. Each agent session is evaluated *individually*: it's "working" if it
/// has sustained API throughput OR CPU in its own process subtree (the latter
/// catches long local tool runs such as test suites or builds that make no
/// network calls). Evaluating per-session — rather than summing across all of
/// them — means a crowd of idle/leftover sessions can't falsely keep the Mac
/// awake.
final class ActivityMonitor {

    var onUpdate: ((ActivitySnapshot) -> Void)?

    private let queue = DispatchQueue(label: "app.vigil.monitor")
    private var timer: DispatchSourceTimer?

    private let semantic = SemanticDetector()

    // Per-PID cumulative byte counters from the previous nettop sample.
    private var prevBytesIn: [Int: UInt64] = [:]
    private var prevSampleDate: Date?

    private let psRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(.*)$"#)

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval = Preferences.shared.pollInterval
        t.schedule(deadline: .now() + 0.2, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        prevBytesIn = [:]
        prevSampleDate = nil
    }

    /// Restart with the latest poll interval (after a preferences change).
    func restart() { start() }

    /// One-shot probe for `--diagnose`: takes two samples ~3s apart (the second
    /// yields a real network delta) and returns the resulting snapshot.
    func diagnostic() -> ActivitySnapshot {
        _ = computeSnapshot()
        Thread.sleep(forTimeInterval: 3)
        return computeSnapshot()
    }

    // MARK: - Polling

    private func tick() {
        deliver(computeSnapshot())
    }

    private func computeSnapshot() -> ActivitySnapshot {
        let prefs = Preferences.shared
        let patterns = prefs.watchPatterns.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return .empty }

        // Primary signal for Claude: transcript state. Counts mid-turn sessions.
        let semanticBusy = prefs.semanticDetection ? semantic.busySessionCount() : 0

        let procs = readProcesses()
        let watched = procs.filter { p in
            let c = p.command.lowercased()
            return patterns.contains { c.contains($0) }
        }
        guard !watched.isEmpty || semanticBusy > 0 else {
            prevBytesIn = [:]
            prevSampleDate = nil
            return .empty
        }

        let watchedPIDs = Set(watched.map { $0.pid })
        let childrenByParent = Dictionary(grouping: procs, by: { $0.ppid })
            .mapValues { $0.map { $0.pid } }
        let cpuByPID = Dictionary(procs.map { ($0.pid, $0.cpu) }, uniquingKeysWith: { a, _ in a })

        // Read network counters once; compute per-PID deltas below.
        let now = Date()
        let bytesIn = readNetBytesIn()
        let elapsed = prevSampleDate.map { now.timeIntervalSince($0) } ?? 0

        // A "session" is a watched process whose parent isn't itself watched.
        // Sessions spawned as siblings (e.g. by an editor's extension host) each
        // count once; their tool children fold into the session's subtree.
        let sessions = watched.filter { !watchedPIDs.contains($0.ppid) }

        var activeCount = 0
        var peakRate = 0.0
        var peakCPU = 0.0

        for session in sessions {
            var subtree = Set<Int>()
            collect(session.pid, childrenByParent, into: &subtree)

            let cpu = subtree.reduce(0.0) { $0 + (cpuByPID[$1] ?? 0) }

            var deltaBytes: UInt64 = 0
            if elapsed > 0.5 {
                for pid in subtree {
                    if let cur = bytesIn[pid], let prev = prevBytesIn[pid], cur >= prev {
                        deltaBytes &+= (cur - prev)
                    }
                }
            }
            let rate = elapsed > 0.5 ? Double(deltaBytes) / elapsed : 0

            // Evaluated per session: a single working agent is enough, and a
            // crowd of idle ones never sums its way over the threshold.
            if rate > prefs.netThresholdBytesPerSec || cpu > prefs.cpuThresholdPercent {
                activeCount += 1
            }
            peakRate = max(peakRate, rate)
            peakCPU = max(peakCPU, cpu)
        }

        prevBytesIn = bytesIn
        prevSampleDate = now

        // Combine the heuristic (network/CPU) with the semantic signal: an agent
        // is working if either says so.
        let totalAgents = max(sessions.count, semanticBusy)
        let activeAgents = max(activeCount, semanticBusy)

        return ActivitySnapshot(agentCount: totalAgents,
                                activeAgentCount: activeAgents,
                                isActive: activeAgents > 0,
                                netBytesPerSec: peakRate,
                                cpuPercent: peakCPU)
    }

    private func collect(_ pid: Int, _ children: [Int: [Int]], into set: inout Set<Int>) {
        guard set.insert(pid).inserted else { return }
        for child in children[pid] ?? [] { collect(child, children, into: &set) }
    }

    private func deliver(_ snapshot: ActivitySnapshot) {
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }

    // MARK: - System probes

    private struct ProcInfo { let pid: Int; let ppid: Int; let cpu: Double; let command: String }

    private func readProcesses() -> [ProcInfo] {
        // `command=` gives the full path + arguments, so presets can match either
        // the executable (e.g. .../native-binary/claude) or CLI args (e.g. `codex`).
        guard let out = run("/bin/ps", ["-axww", "-o", "pid=,ppid=,pcpu=,command="]) else { return [] }
        var result: [ProcInfo] = []
        out.enumerateLines { line, _ in
            let range = NSRange(line.startIndex..., in: line)
            guard let m = self.psRegex.firstMatch(in: line, range: range),
                  let pidR = Range(m.range(at: 1), in: line),
                  let ppidR = Range(m.range(at: 2), in: line),
                  let cpuR = Range(m.range(at: 3), in: line),
                  let cmdR = Range(m.range(at: 4), in: line),
                  let pid = Int(line[pidR]),
                  let ppid = Int(line[ppidR]) else { return }
            let cpu = Double(line[cpuR]) ?? 0
            result.append(ProcInfo(pid: pid, ppid: ppid, cpu: cpu, command: String(line[cmdR])))
        }
        return result
    }

    /// Returns cumulative bytes_in per PID from a single nettop sample.
    private func readNetBytesIn() -> [Int: UInt64] {
        guard let out = run("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-t", "external"]) else { return [:] }
        var result: [Int: UInt64] = [:]
        var first = true
        out.enumerateLines { line, _ in
            if first { first = false; return } // header
            let fields = line.components(separatedBy: ",")
            guard fields.count > 5 else { return }
            let nameDotPid = fields[1]
            guard let dot = nameDotPid.lastIndex(of: "."),
                  let pid = Int(nameDotPid[nameDotPid.index(after: dot)...]),
                  let bytes = UInt64(fields[4]) else { return }
            result[pid, default: 0] &+= bytes
        }
        return result
    }

    private func run(_ launchPath: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
