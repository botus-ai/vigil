import Foundation
import IOKit.pwr_mgt

/// Owns the IOKit power assertions that keep the Mac awake with the lid OPEN.
/// Lid-closed (clamshell) sleep is handled separately by ClamshellController,
/// because power assertions cannot block a lid-close sleep event.
final class SleepController {

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemHeld = false
    private var displayHeld = false

    // Prevents App Nap from throttling our polling timer while we're keeping the
    // Mac awake — critical with the lid closed, where a napped timer would let the
    // heartbeat go stale and the clamshell helper would re-enable sleep.
    private var activity: NSObjectProtocol?

    private let reason = "Vigil: AI agent active" as CFString

    var isHoldingAwake: Bool { systemHeld }

    /// Create/release assertions to match the desired awake state.
    /// - keepDisplayAwake: also prevent the display from sleeping.
    func apply(awake: Bool, keepDisplayAwake: Bool) {
        if awake {
            acquireSystem()
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated], reason: "Keeping the Mac awake for AI agents")
            }
            if keepDisplayAwake { acquireDisplay() } else { releaseDisplay() }
        } else {
            releaseDisplay()
            releaseSystem()
            if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        }
    }

    private func acquireSystem() {
        guard !systemHeld else { return }
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemAssertionID)
        systemHeld = (rc == kIOReturnSuccess)
    }

    private func releaseSystem() {
        guard systemHeld else { return }
        IOPMAssertionRelease(systemAssertionID)
        systemAssertionID = 0
        systemHeld = false
    }

    private func acquireDisplay() {
        guard !displayHeld else { return }
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertionID)
        displayHeld = (rc == kIOReturnSuccess)
    }

    private func releaseDisplay() {
        guard displayHeld else { return }
        IOPMAssertionRelease(displayAssertionID)
        displayAssertionID = 0
        displayHeld = false
    }

    /// Release everything (called on quit).
    func releaseAll() {
        releaseDisplay()
        releaseSystem()
    }
}
