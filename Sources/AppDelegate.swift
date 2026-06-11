import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    private var menu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One-time migration: the display-keep-awake default flipped to OFF in
        // 1.1.3 (it relit the panel behind a closed lid). Clear any stored "true"
        // from older builds so existing users get the new default; they can still
        // turn it back on from the menu.
        let d = UserDefaults.standard
        if !d.bool(forKey: "migratedDisplayDefault113") {
            d.removeObject(forKey: "keepDisplayAwake")
            d.set(true, forKey: "migratedDisplayDefault113")
        }

        menu = StatusMenuController(controller: controller)
        controller.start()

        // Re-protect a running agent the instant the Mac wakes from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Out of the box: start at login unless the user has turned it off.
        if !Preferences.shared.loginItemUserDisabled {
            LaunchAtLogin.set(true)
        }

        // Out of the box: install the ground-truth Claude Code hook (merged into
        // ~/.claude/settings.json with a one-time backup; removable from the menu).
        // Called every launch: the settings merge is idempotent, and rewriting
        // the hook script keeps it current across app updates.
        if Preferences.shared.hooksEnabled, !HooksInstaller().install() {
            NSLog("Vigil: hook install failed — falling back to transcript/heuristic detection")
        }

        // First-run welcome + optional lid-closed setup (after the menu appears).
        if !Preferences.shared.didOnboard {
            Preferences.shared.didOnboard = true
            DispatchQueue.main.async { [weak self] in self?.menu?.runOnboarding() }
        }
    }

    @objc private func systemDidWake() {
        controller.systemDidWake()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
