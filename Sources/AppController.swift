import Foundation

struct VigilStatus {
    var mode: OperatingMode
    var holdingAwake: Bool           // currently preventing sleep
    var lidClosedActive: Bool        // lid-closed mode engaged right now
    var snapshot: ActivitySnapshot
    var redundantCount: Int          // other keep-awake tools that could be stopped
}

/// Ties detection, power assertions and clamshell together, applying the
/// operating mode plus the grace period.
final class AppController {

    let clamshell = ClamshellController()
    let cleanup = CleanupController()
    private let monitor = ActivityMonitor()
    private let sleep = SleepController()

    private var lastActive = Date.distantPast
    private var lastSnapshot = ActivitySnapshot.empty

    /// Called on the main thread whenever the visible status changes.
    var onStatusChange: ((VigilStatus) -> Void)?

    func start() {
        monitor.onUpdate = { [weak self] snap in self?.handle(snap) }
        monitor.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged),
            name: .vigilPreferencesChanged, object: nil)
        evaluate()
    }

    @objc private func prefsChanged() {
        monitor.restart()
        evaluate()
    }

    /// Re-emit the current status (e.g. after a toggle that doesn't change prefs).
    func refreshStatus() { evaluate() }

    private func handle(_ snap: ActivitySnapshot) {
        lastSnapshot = snap
        if snap.isActive { lastActive = Date() }
        evaluate()
    }

    private func evaluate() {
        let prefs = Preferences.shared
        let engaged: Bool
        switch prefs.mode {
        case .off:
            engaged = false
        case .keepAwake:
            engaged = true
        case .automatic:
            engaged = Date().timeIntervalSince(lastActive) < prefs.gracePeriod
        }

        if ProcessInfo.processInfo.environment["VIGIL_DEBUG"] != nil {
            NSLog("VIGIL mode=\(prefs.mode.rawValue) patterns=\(prefs.watchPatterns) agents=\(lastSnapshot.agentCount) active=\(lastSnapshot.activeAgentCount) isActive=\(lastSnapshot.isActive) engaged=\(engaged)")
        }
        sleep.apply(awake: engaged, keepDisplayAwake: prefs.keepDisplayAwake && engaged)

        let lidWanted = engaged && prefs.lidClosedMode
        if clamshell.isHelperInstalled {
            clamshell.heartbeat(engaged: lidWanted)
        }

        // Other keep-awake tools are redundant while Vigil is in charge.
        let redundant = (prefs.mode == .off) ? [] : cleanup.find()
        if prefs.autoCleanRedundant && !redundant.isEmpty {
            cleanup.stop(redundant)
        }

        onStatusChange?(VigilStatus(
            mode: prefs.mode,
            holdingAwake: engaged,
            lidClosedActive: lidWanted && clamshell.isHelperInstalled,
            snapshot: lastSnapshot,
            redundantCount: prefs.autoCleanRedundant ? 0 : redundant.count))
    }

    func shutdown() {
        monitor.stop()
        sleep.releaseAll()
        if clamshell.isHelperInstalled { clamshell.heartbeat(engaged: false) }
    }
}
