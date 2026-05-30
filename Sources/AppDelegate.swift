import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    private var menu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
