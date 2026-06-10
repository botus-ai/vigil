import Foundation

/// Installs Vigil's ground-truth hook into ~/.claude/settings.json (user level).
///
/// Safety rules, in order of importance:
///  • NEVER touch a settings.json we cannot parse — refuse instead.
///  • One-time backup to settings.json.vigil-backup before the first change.
///  • Merge: only append our entries; never remove or reorder the user's hooks
///    or any other key.
///  • Idempotent: re-running install adds nothing if our entries are present.
final class HooksInstaller {

    static let marker = "vigil-hook.py"

    private var settingsPath: String { NSHomeDirectory() + "/.claude/settings.json" }
    private var backupPath: String { NSHomeDirectory() + "/.claude/settings.json.vigil-backup" }
    private var scriptPath: String { NSHomeDirectory() + "/Library/Application Support/Vigil/vigil-hook.py" }

    /// (event, matcher) pairs to register. PreToolUse/PostToolUse take a tool
    /// matcher ("*" = all tools); the other events take none.
    private let events: [(name: String, matcher: String?)] = [
        ("UserPromptSubmit", nil),   // turn started → active
        ("PreToolUse", "*"),         // tool starting → active (also clears "waiting" after permission grant)
        ("PostToolUse", "*"),        // tool finished → refresh active
        ("Notification", nil),       // permission prompt / waiting for input → human needed
        ("Stop", nil),               // turn finished → idle
        ("SessionEnd", nil),         // session closed → idle
    ]

    var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: scriptPath),
              let s = try? String(contentsOfFile: settingsPath, encoding: .utf8) else { return false }
        return s.contains(Self.marker)
    }

    @discardableResult
    func install() -> Bool {
        // 1. The hook script itself.
        do {
            let dir = (scriptPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: HookSessionDetector.sessionsDir,
                                                    withIntermediateDirectories: true)
            try hookScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            NSLog("Vigil: failed to write hook script: \(error)")
            return false
        }

        // 2. Merge into settings.json.
        var root: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                NSLog("Vigil: ~/.claude/settings.json is not parseable JSON — refusing to modify it")
                return false
            }
            root = parsed
            if !FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.copyItem(atPath: settingsPath, toPath: backupPath)
            }
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "/usr/bin/python3 \"\(scriptPath)\""
        var changed = false
        for spec in events {
            var entries = hooks[spec.name] as? [[String: Any]] ?? []
            if entries.contains(where: { Self.entryIsOurs($0) }) { continue }
            var entry: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": 10]],
            ]
            if let m = spec.matcher { entry["matcher"] = m }
            entries.append(entry)
            hooks[spec.name] = entries
            changed = true
        }
        guard changed else { return true }
        root["hooks"] = hooks
        return write(root)
    }

    @discardableResult
    func uninstall() -> Bool {
        try? FileManager.default.removeItem(atPath: scriptPath)
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else { return true }
        var changed = false
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            let before = entries.count
            entries.removeAll(where: { Self.entryIsOurs($0) })
            if entries.count != before {
                hooks[event] = entries.isEmpty ? nil : entries
                changed = true
            }
        }
        guard changed else { return true }
        root["hooks"] = hooks
        return write(root)
    }

    private static func entryIsOurs(_ entry: [String: Any]) -> Bool {
        ((entry["hooks"] as? [[String: Any]]) ?? []).contains {
            ($0["command"] as? String)?.contains(marker) == true
        }
    }

    private func write(_ root: [String: Any]) -> Bool {
        guard let out = try? JSONSerialization.data(withJSONObject: root,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try out.write(to: URL(fileURLWithPath: settingsPath))
            return true
        } catch {
            NSLog("Vigil: failed to write settings.json: \(error)")
            return false
        }
    }

    // MARK: - The hook script

    private var hookScript: String {
        """
        #!/usr/bin/env python3
        # Vigil hook — records Claude Code session activity (ground truth).
        # Installed by Vigil.app; removed via its menu ("Precise detection").
        # Receives the hook event JSON on stdin, writes one tiny marker file per
        # session: "<state> <claude-pid> <unix-ts>".
        import json, os, sys, time, subprocess

        D = os.path.expanduser("~/Library/Application Support/Vigil/sessions")

        def write_marker(sid, state, pid):
            try:
                os.makedirs(D, exist_ok=True)
                with open(os.path.join(D, sid), "w") as f:
                    f.write(f"{state} {pid} {int(time.time())}")
            except OSError:
                pass

        def claude_pid():
            # Walk up the parent chain to the claude process that invoked us
            # (hook commands run under a shell, so the direct parent may be sh).
            # Tight caps: this is best-effort enrichment, never worth blocking on.
            pid = os.getppid()
            for _ in range(3):
                if pid <= 1:
                    break
                try:
                    out = subprocess.run(
                        ["/bin/ps", "-o", "ppid=,command=", "-p", str(pid)],
                        capture_output=True, text=True, timeout=1,
                    ).stdout.strip()
                except Exception:
                    break
                if not out:
                    break
                parts = out.split(None, 1)
                cmd = parts[1] if len(parts) > 1 else ""
                if "claude" in cmd.lower():
                    return pid
                try:
                    pid = int(parts[0])
                except ValueError:
                    break
            return 0

        try:
            data = json.load(sys.stdin)
        except Exception:
            sys.exit(0)
        sid = str(data.get("session_id") or "unknown").replace("/", "_").replace("..", "_")[:100]
        event = data.get("hook_event_name") or ""
        if event in ("Stop", "SessionEnd"):
            write_marker(sid, "idle", 0)
        elif event == "Notification":
            # Permission prompt or waiting-for-input: a human is needed; the
            # agent is NOT working. Next PreToolUse/UserPromptSubmit re-activates.
            write_marker(sid, "waiting", 0)
        else:
            # Land the event IMMEDIATELY (so a slow ps can never lose it), then
            # enrich with the claude pid for the liveness check.
            write_marker(sid, "active", 0)
            pid = claude_pid()
            if pid > 0:
                write_marker(sid, "active", pid)
        sys.exit(0)
        """
    }
}
