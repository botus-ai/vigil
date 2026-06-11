import Foundation
import IOKit

enum LidState {
    /// True when the MacBook lid is closed (AppleClamshellState in IOPMrootDomain).
    /// VIGIL_FAKE_LID=closed/open overrides for deterministic tests.
    static var isClosed: Bool {
        if let fake = ProcessInfo.processInfo.environment["VIGIL_FAKE_LID"] {
            return fake == "closed"
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return false }
        return (prop as? Bool) ?? false
    }
}
