import Foundation

/// Keeps the Mac awake with the lid CLOSED. Power assertions can't do this, so
/// we use the documented `pmset disablesleep` flag, which requires root.
///
/// To avoid a password prompt on every toggle, we install a tiny LaunchDaemon
/// (once, with one admin authorization). The app then drops a heartbeat file in
/// its own home folder; the root daemon reads it every few seconds and sets
/// `disablesleep` accordingly. Crucially, if the heartbeat goes stale (app quit
/// or crashed) the daemon resets `disablesleep 0` — sleep is always restored.
final class ClamshellController {

    static let label = "app.vigil.clamshelld"
    private static let staleSeconds = 30
    private static let daemonInterval = 15

    private let fm = FileManager.default

    private var stateFile: String {
        "\(NSHomeDirectory())/Library/Application Support/Vigil/clamshell.state"
    }
    private var plistPath: String { "/Library/LaunchDaemons/\(Self.label).plist" }
    private var daemonScriptPath: String { "/Library/Application Support/Vigil/clamshelld.sh" }

    var isHelperInstalled: Bool { fm.fileExists(atPath: plistPath) }

    // MARK: - Heartbeat (no privileges needed)

    /// Write the heartbeat. `engaged == true` asks the daemon to disable sleep;
    /// the write also refreshes the file's mtime so the daemon sees it as fresh.
    func heartbeat(engaged: Bool) {
        let dir = (stateFile as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? (engaged ? "1" : "0").write(toFile: stateFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Install / uninstall (one admin prompt)

    func installHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global().async {
            let result = Result { try self.runInstall() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func uninstallHelper(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global().async {
            let result = Result { try self.runUninstall() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func runInstall() throws {
        let dir = (stateFile as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "0".write(toFile: stateFile, atomically: true, encoding: .utf8)

        let tmp = NSTemporaryDirectory()
        let tmpScript = tmp + "vigil-clamshelld.sh"
        let tmpPlist = tmp + "vigil-clamshelld.plist"
        let tmpInstall = tmp + "vigil-install.sh"

        try daemonScript().write(toFile: tmpScript, atomically: true, encoding: .utf8)
        try launchDaemonPlist().write(toFile: tmpPlist, atomically: true, encoding: .utf8)

        let install = """
        #!/bin/bash
        set -e
        mkdir -p "/Library/Application Support/Vigil"
        cp "\(tmpScript)" "\(daemonScriptPath)"
        chown root:wheel "\(daemonScriptPath)"
        chmod 755 "\(daemonScriptPath)"
        cp "\(tmpPlist)" "\(plistPath)"
        chown root:wheel "\(plistPath)"
        chmod 644 "\(plistPath)"
        launchctl bootout system "\(plistPath)" 2>/dev/null || true
        launchctl bootstrap system "\(plistPath)"
        """
        try install.write(toFile: tmpInstall, atomically: true, encoding: .utf8)
        try runPrivileged(script: tmpInstall)
    }

    private func runUninstall() throws {
        // Best effort: tell the daemon to allow sleep before removing it.
        heartbeat(engaged: false)
        let tmp = NSTemporaryDirectory()
        let tmpUninstall = tmp + "vigil-uninstall.sh"
        let uninstall = """
        #!/bin/bash
        launchctl bootout system "\(plistPath)" 2>/dev/null || true
        pmset -a disablesleep 0 || true
        rm -f "\(plistPath)"
        rm -f "\(daemonScriptPath)"
        """
        try uninstall.write(toFile: tmpUninstall, atomically: true, encoding: .utf8)
        try runPrivileged(script: tmpUninstall)
    }

    /// Runs a script as root via the standard macOS authorization dialog.
    private func runPrivileged(script path: String) throws {
        let osa = "do shell script \"/bin/bash '\(path)'\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osa]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Vigil.Clamshell", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Authorization failed or cancelled." : msg])
        }
    }

    /// Write the generated daemon script + plist to a directory (for inspection /
    /// testing). Does not install anything or require privileges.
    func writeArtifacts(toDirectory dir: String) throws {
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try daemonScript().write(toFile: dir + "/clamshelld.sh", atomically: true, encoding: .utf8)
        try launchDaemonPlist().write(toFile: dir + "/\(Self.label).plist", atomically: true, encoding: .utf8)
    }

    // MARK: - Generated helper artifacts

    private func daemonScript() -> String {
        """
        #!/bin/bash
        # Vigil clamshell helper. Reads a heartbeat file written by the Vigil app
        # and toggles `pmset disablesleep`. If the heartbeat is missing or stale,
        # sleep is re-enabled so the Mac can never get stuck awake.
        STATE_FILE="\(stateFile)"
        WANT=0
        if [ -f "$STATE_FILE" ]; then
          NOW=$(date +%s)
          MTIME=$(stat -f %m "$STATE_FILE" 2>/dev/null || echo 0)
          CONTENT=$(cat "$STATE_FILE" 2>/dev/null)
          AGE=$((NOW - MTIME))
          if [ "$CONTENT" = "1" ] && [ "$AGE" -le \(Self.staleSeconds) ]; then
            WANT=1
          fi
        fi
        /usr/bin/pmset -a disablesleep $WANT
        """
    }

    private func launchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(daemonScriptPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>\(Self.daemonInterval)</integer>
            <key>WatchPaths</key>
            <array>
                <string>\(stateFile)</string>
            </array>
            <key>StandardErrorPath</key>
            <string>/dev/null</string>
            <key>StandardOutPath</key>
            <string>/dev/null</string>
        </dict>
        </plist>
        """
    }
}
