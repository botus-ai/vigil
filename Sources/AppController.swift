import Foundation

struct VigilStatus {
    var mode: OperatingMode
    var holdingAwake: Bool           // currently preventing sleep
    var lidClosedActive: Bool        // lid-closed mode engaged right now
    var snapshot: ActivitySnapshot
    var redundantCount: Int          // other keep-awake tools that could be stopped
    var degraded: Bool               // wanted an assertion the OS refused to grant
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

    // Debounce the work-STARTED edge: require a couple of consecutive active polls
    // before we treat an agent as working. A single CPU/transcript blip from a
    // background job can't then arm a long keep-awake hold (the "never sleeps"
    // regression). Once engaged, the grace period governs the quiet tail.
    private var consecutiveActiveTicks = 0
    private let activateAfterTicks = 2

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

    /// Call when the Mac wakes from sleep: re-protect a still-running agent
    /// immediately and give it a fresh grace window instead of resuming on stale
    /// data (which could let the Mac instantly re-sleep on a live agent).
    func systemDidWake() {
        lastActive = Date()
        sleep.reacquireIfHolding()
        monitor.restart()
        evaluate()
    }

    private func handle(_ snap: ActivitySnapshot) {
        lastSnapshot = snap
        if snap.isActive {
            consecutiveActiveTicks += 1
        } else {
            consecutiveActiveTicks = 0
        }
        if consecutiveActiveTicks >= activateAfterTicks {
            lastActive = Date()
        }
        evaluate()
    }

    /// Whether an agent is confirmed working right now (after debounce).
    private var liveActive: Bool { consecutiveActiveTicks >= activateAfterTicks }

    private func evaluate() {
        let prefs = Preferences.shared
        let engaged: Bool
        switch prefs.mode {
        case .off:
            engaged = false
        case .keepAwake:
            engaged = true
        case .automatic:
            // Stay awake while an agent is confirmed working, OR within the grace
            // tail after work last stopped. Honouring the live signal (not just a
            // decaying timestamp) means a mid-turn agent is never slept.
            engaged = liveActive || Date().timeIntervalSince(lastActive) < prefs.gracePeriod
        }

        // Hold the display awake for the WHOLE engaged window (not just while
        // actively working), so the screen never sleeps/locks mid-task. Forced on
        // in keepAwake mode regardless of the toggle.
        let wantDisplay = (prefs.mode == .keepAwake || prefs.keepDisplayAwake) && engaged

        if ProcessInfo.processInfo.environment["VIGIL_DEBUG"] != nil {
            NSLog("VIGIL mode=\(prefs.mode.rawValue) agents=\(lastSnapshot.agentCount) active=\(lastSnapshot.activeAgentCount) isActive=\(lastSnapshot.isActive) ticks=\(consecutiveActiveTicks) engaged=\(engaged) display=\(wantDisplay)")
        }
        sleep.apply(awake: engaged, keepDisplayAwake: wantDisplay)

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
            redundantCount: prefs.autoCleanRedundant ? 0 : redundant.count,
            degraded: sleep.degraded))
    }

    func shutdown() {
        monitor.stop()
        sleep.releaseAll()
        if clamshell.isHelperInstalled { clamshell.heartbeat(engaged: false) }
    }
}
