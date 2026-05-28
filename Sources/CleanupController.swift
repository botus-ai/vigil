import Foundation
import Darwin

struct RedundantProcess {
    let pid: Int
    let reason: String       // short label, e.g. "caffeinate"
    let command: String      // full command line, for the confirmation list
}

/// Finds and stops *other* keep-awake tools that become redundant once Vigil is
/// managing sleep — the `caffeinate` CLI and DIY keep-awake scripts. Only the
/// current user's processes are considered, so system/root keep-awake tasks are
/// never touched.
final class CleanupController {

    func find() -> [RedundantProcess] {
        guard let out = run("/bin/ps", ["-xww", "-o", "pid=,command="]) else { return [] }
        var result: [RedundantProcess] = []
        out.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int(trimmed[..<space]) else { return }
            let command = String(trimmed[trimmed.index(after: space)...])
            let lc = command.lowercased()

            // Never touch Vigil itself or its helper daemon.
            if lc.contains("vigil") || lc.contains("clamshelld") { return }

            let reason: String
            if lc.contains("caffeinate") {
                reason = "caffeinate"
            } else if lc.contains("keep-awake") || lc.contains("keepawake") || lc.contains("nosleep") {
                reason = "keep-awake script"
            } else {
                return
            }
            result.append(RedundantProcess(pid: pid, reason: reason, command: command))
        }
        return result
    }

    /// SIGTERM the given processes (scripts first, so they don't respawn their
    /// caffeinate child after we kill it). Returns how many were signalled.
    @discardableResult
    func stop(_ procs: [RedundantProcess]) -> Int {
        let ordered = procs.sorted { $0.reason == "keep-awake script" && $1.reason != "keep-awake script" }
        var count = 0
        for p in ordered {
            if kill(pid_t(p.pid), SIGTERM) == 0 { count += 1 }
        }
        return count
    }

    private func run(_ launchPath: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
