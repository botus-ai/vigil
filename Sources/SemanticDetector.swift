import Foundation

/// Claude-specific activity detection by reading session transcripts in
/// ~/.claude/projects/**.jsonl. A session is "busy" when its most recent *turn*
/// record shows it's mid-turn — a pending user/tool message, or an assistant
/// message whose stop_reason isn't terminal. This is more precise than
/// network/CPU heuristics: it knows an agent is working even during a quiet
/// pause (model thinking, a slow tool) when CPU and network are near zero.
///
/// Two robustness rules learned the hard way:
///
///  • Ignore metadata. Claude Code transcripts interleave conversation records
///    (`user`, `assistant`) with many *metadata* records (`mode`, `ai-title`,
///    `last-prompt`, `queue-operation`, `system`, `attachment`,
///    `file-history-snapshot`, …) written constantly — including after a turn
///    ends. We do NOT enumerate metadata types to skip (that list is open-ended;
///    missing one silently breaks detection). We scan backwards for the last
///    record that is specifically a `user` or `assistant` turn and judge that.
///
///  • Judge staleness from the RECORD's own timestamp, never the file mtime.
///    Trailing metadata records refresh the file mtime without advancing the
///    conversation, so an abandoned/long-finished turn would look "fresh" by
///    mtime and wrongly keep the Mac awake. Each user/assistant record carries
///    an ISO-8601 `timestamp`; we use that. File mtime is only a cheap
///    pre-filter to avoid reading ancient transcripts.
final class SemanticDetector {

    /// Don't even open transcripts whose file hasn't changed in this long.
    private let fileSkipWindow: TimeInterval = 3600
    /// An assistant mid-turn record older than this (by its own timestamp) is
    /// treated as stuck/abandoned → idle. Also bounds how long a silent local
    /// tool keeps the Mac awake on the semantic signal alone (~15 min); longer
    /// tools are covered by the CPU/network heuristic or Keep Awake mode.
    private let midTurnWindow: TimeInterval = 900
    /// A pending user/tool_result unanswered this long → the assistant isn't
    /// actually working (a working assistant writes within seconds).
    private let userPendingStale: TimeInterval = 180

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static func parseTimestamp(_ s: String) -> Date? {
        Self.isoFrac.date(from: s) ?? Self.isoPlain.date(from: s)
    }

    private var projectsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: projectsDir.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Number of Claude sessions currently mid-turn.
    func busySessionCount() -> Int {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return 0 }

        let now = Date()
        var busy = 0
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = vals.contentModificationDate else { continue }
            let fileAge = now.timeIntervalSince(mtime)
            if fileAge > fileSkipWindow { continue }   // cheap pre-filter only
            if isBusy(url, now: now, fileAge: fileAge) { busy += 1 }
        }
        return busy
    }

    private enum TurnKind { case user, assistant }
    private struct Turn { var kind: TurnKind; var stopReason: String?; var timestamp: Date? }

    private func isBusy(_ url: URL, now: Date, fileAge: TimeInterval) -> Bool {
        guard let turn = lastTurn(url) else { return false }
        // Age of the turn itself, from its own timestamp; fall back to file mtime
        // only if the record carries no parseable timestamp.
        let age = turn.timestamp.map { now.timeIntervalSince($0) } ?? fileAge
        switch turn.kind {
        case .assistant:
            // Terminal reasons mean the turn is over, waiting for the human → idle.
            // Everything else (nil = streaming, tool_use, pause_turn, or any
            // unknown/future reason) is treated as still working — bias to awake.
            if isTerminal(turn.stopReason) { return false }
            return age < midTurnWindow
        case .user:
            // Pending user/tool_result: the assistant owes a response. Only counts
            // while genuinely fresh — a long-unanswered message is stuck/idle.
            return age < userPendingStale
        }
    }

    private func isTerminal(_ stopReason: String?) -> Bool {
        guard let sr = stopReason else { return false }   // nil = still streaming
        return sr == "end_turn" || sr == "stop_sequence" || sr == "max_tokens" || sr == "refusal"
    }

    /// Scan the tail backwards for the last `user`/`assistant` turn record.
    private func lastTurn(_ url: URL) -> Turn? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        // Read a generous tail so the last user/assistant record is included even
        // after a burst of trailing metadata records (observed up to ~15 KB; 128 KB
        // gives a large margin). Tool results are top-level `user` records, so they
        // are matched normally — there is no separate `tool_result` record type.
        let tail: UInt64 = 131_072
        handle.seek(toFileOffset: size > tail ? size - tail : 0)
        guard let data = try? handle.readToEnd(), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            let ts = (obj["timestamp"] as? String).flatMap(Self.parseTimestamp)
            switch type {
            case "assistant":
                let sr = (obj["message"] as? [String: Any])?["stop_reason"] as? String
                return Turn(kind: .assistant, stopReason: sr, timestamp: ts)
            case "user":
                return Turn(kind: .user, stopReason: nil, timestamp: ts)
            default:
                continue   // metadata (mode/ai-title/system/…) — keep scanning back
            }
        }
        return nil
    }
}
