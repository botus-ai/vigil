import Foundation

struct HookScan {
    var governedSessions: Set<String>   // session ids that have any marker (hooks are live for them)
    var activeCount: Int                // sessions confirmed mid-turn right now
    var waitingCount: Int               // sessions waiting for the human (permission / idle prompt)
    var activeSessions: [String]        // session ids currently keeping the Mac awake

    static let empty = HookScan(governedSessions: [], activeCount: 0, waitingCount: 0, activeSessions: [])
}

/// Ground-truth activity detection via Claude Code hooks.
///
/// Vigil installs a tiny hook script into ~/.claude/settings.json (see
/// HooksInstaller). Claude Code then *tells us* what each session is doing:
///   UserPromptSubmit / PreToolUse / PostToolUse → "active <claude-pid> <ts>"
///   Notification (permission prompt / waiting for input) → "waiting 0 <ts>"
///   Stop / SessionEnd → "idle 0 <ts>"
/// One marker file per session id. This replaces guessing from transcript
/// formats and CPU/network thresholds with events emitted by Claude Code
/// itself — instant on turn start, instant on turn end.
///
/// Crash-safety: an "active" marker is only honoured while the recorded claude
/// process is still alive, and never longer than `activeTrustWindow` without a
/// refresh (a turn that long without a single tool call means a dead/hung
/// session — multi-tool turns refresh on every PostToolUse).
final class HookSessionDetector {

    static var sessionsDir: String {
        if let o = ProcessInfo.processInfo.environment["VIGIL_SESSIONS_DIR"], !o.isEmpty { return o }
        return NSHomeDirectory() + "/Library/Application Support/Vigil/sessions"
    }

    private let activeTrustWindow: TimeInterval = 2 * 3600
    /// An "active" marker with no recorded pid (the hook couldn't identify its
    /// claude process) is weaker evidence — trust it only briefly.
    private let pidlessTrustWindow: TimeInterval = 600
    /// Markers older than this get cross-checked against the transcript, which
    /// catches a lost Stop event (turn actually ended but the idle marker never
    /// arrived, e.g. the hook was killed at the wrong moment).
    private let crossCheckAge: TimeInterval = 600
    private let markerTTL: TimeInterval = 48 * 3600

    /// Injected: returns true if the session's transcript shows the turn ENDED
    /// after the given marker time (terminal stop_reason with a newer timestamp).
    var transcriptSaysEnded: ((String, Date) -> Bool)?

    func scan() -> HookScan {
        var result = HookScan.empty
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.sessionsDir) else { return result }
        let now = Date().timeIntervalSince1970
        for name in names where !name.hasPrefix(".") {
            let path = Self.sessionsDir + "/" + name
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let parts = content.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            guard parts.count >= 3,
                  let pid = Int32(parts[1]),
                  let ts = TimeInterval(parts[2]) else { continue }
            let age = now - ts
            if age > markerTTL { try? fm.removeItem(atPath: path); continue }
            result.governedSessions.insert(name)
            switch parts[0] {
            case "active":
                var ok: Bool
                if pid > 0 {
                    // Strong evidence: the claude process must still be alive,
                    // bounded by the trust window (multi-tool turns refresh on
                    // every PostToolUse; a single silent tool is covered up to
                    // the window).
                    ok = processAlive(pid) && age < activeTrustWindow
                } else {
                    ok = age < pidlessTrustWindow
                }
                // Lost-Stop guard: if the marker is old but the transcript shows
                // the turn ended AFTER it was written, the idle event was lost —
                // don't keep the Mac awake on a finished turn.
                if ok, age > crossCheckAge,
                   let ended = transcriptSaysEnded,
                   ended(name, Date(timeIntervalSince1970: ts)) {
                    ok = false
                }
                if ok { result.activeCount += 1; result.activeSessions.append(name) }
            case "waiting":
                result.waitingCount += 1
            default:
                break   // idle
            }
        }
        return result
    }

    private func processAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
