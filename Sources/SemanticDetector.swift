import Foundation

/// Claude-specific activity detection by reading session transcripts in
/// ~/.claude/projects/*.jsonl. A session is "busy" when its last meaningful
/// record shows it's mid-turn (a pending user/tool message, or an assistant
/// message whose stop_reason isn't "end_turn"). This is more precise than
/// network/CPU heuristics: it knows an agent is working even during a quiet
/// pause between an API turn and the next tool call.
final class SemanticDetector {

    private let metaTypes: Set<String> = [
        "ai-title", "last-prompt", "custom-title", "file-history-snapshot",
        "queue-operation", "attachment", "system",
    ]
    private let recentWindow: TimeInterval = 900   // ignore transcripts older than 15 min
    private let zombieAge: TimeInterval = 180      // mid-turn but stale 3 min → abandoned

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
            let age = now.timeIntervalSince(mtime)
            if age > recentWindow { continue }
            if isBusy(url, age: age) { busy += 1 }
        }
        return busy
    }

    private func isBusy(_ url: URL, age: TimeInterval) -> Bool {
        guard let obj = lastMeaningfulRecord(url) else { return false }
        switch obj["type"] as? String {
        case "user":
            // A pending user message or tool_result means the assistant should be
            // working — unless it's gone stale (crashed/abandoned session).
            return age <= zombieAge
        case "assistant":
            let msg = obj["message"] as? [String: Any] ?? [:]
            if msg["stop_reason"] as? String == "end_turn" { return false }
            // tool_use / max_tokens / pause_turn / null → still working.
            return age <= zombieAge
        default:
            return false
        }
    }

    /// Read the tail of the file and return the last non-metadata JSON record.
    private func lastMeaningfulRecord(_ url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        let tail: UInt64 = 8192
        handle.seek(toFileOffset: size > tail ? size - tail : 0)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let type = obj["type"] as? String, metaTypes.contains(type) { continue }
            return obj
        }
        return nil
    }
}
