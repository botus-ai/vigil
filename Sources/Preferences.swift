import Foundation

enum OperatingMode: String {
    case automatic   // watch for AI agents and keep awake only while they work
    case keepAwake   // force-awake regardless of activity (manual, like Amphetamine)
    case off         // never prevent sleep
}

/// User-facing settings, backed by UserDefaults. Posts `.vigilPreferencesChanged`
/// whenever a value changes so controllers can react live.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let mode = "mode"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let lidClosedMode = "lidClosedMode"
        static let gracePeriod = "gracePeriodSeconds"
        static let pollInterval = "pollIntervalSeconds"
        static let netThreshold = "netThresholdBytesPerSec"
        static let cpuThreshold = "cpuThresholdPercent"
        static let watchPatterns = "watchPatterns"
        static let watchExcludes = "watchExcludes"
        static let autoCleanRedundant = "autoCleanRedundant"
        static let semanticDetection = "semanticDetection"
        static let hooksEnabled = "hooksEnabled"
        static let guiBurstWindow = "guiBurstWindowSeconds"
        static let didOnboard = "didOnboard"
        static let loginItemUserDisabled = "loginItemUserDisabled"
    }

    /// Substrings that, if present in a process command line, EXCLUDE it from
    /// being treated as an agent — even if it matches a watch pattern. This stops
    /// "claude"-named background tooling (vault sync, memory daemons, this app's
    /// own helper) from being misread as a working agent and pinning the Mac awake.
    static let defaultExcludes = [
        "claude-mem", "claude-history", ".claude/statsig", "obsidian",
        "vault-sync", "vault auto-sync", "chat-auditor", "keep-awake",
        "vigil", "clamshelld",
    ]

    private init() {
        defaults.register(defaults: [
            Key.mode: OperatingMode.automatic.rawValue,
            Key.keepDisplayAwake: true,
            Key.lidClosedMode: false,
            Key.gracePeriod: 120.0,
            Key.pollInterval: 5.0,
            Key.netThreshold: 2048.0,
            Key.cpuThreshold: 5.0,
            Key.watchPatterns: ["claude"],
            Key.watchExcludes: Preferences.defaultExcludes,
            Key.autoCleanRedundant: false,
            Key.semanticDetection: true,
            Key.hooksEnabled: true,
            Key.guiBurstWindow: 300.0,
        ])
    }

    private func changed() {
        NotificationCenter.default.post(name: .vigilPreferencesChanged, object: nil)
    }

    var mode: OperatingMode {
        get { OperatingMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.mode); changed() }
    }

    var keepDisplayAwake: Bool {
        get { defaults.bool(forKey: Key.keepDisplayAwake) }
        set { defaults.set(newValue, forKey: Key.keepDisplayAwake); changed() }
    }

    /// Keep the Mac awake even with the lid closed (requires the privileged helper).
    var lidClosedMode: Bool {
        get { defaults.bool(forKey: Key.lidClosedMode) }
        set { defaults.set(newValue, forKey: Key.lidClosedMode); changed() }
    }

    /// Seconds of no detected activity before we let the Mac sleep again.
    var gracePeriod: TimeInterval {
        get { defaults.double(forKey: Key.gracePeriod) }
        set { defaults.set(newValue, forKey: Key.gracePeriod); changed() }
    }

    var pollInterval: TimeInterval {
        get { max(2.0, defaults.double(forKey: Key.pollInterval)) }
        set { defaults.set(newValue, forKey: Key.pollInterval); changed() }
    }

    /// Bytes/sec of API traffic from a watched process that counts as "working".
    var netThresholdBytesPerSec: Double {
        get { defaults.double(forKey: Key.netThreshold) }
        set { defaults.set(newValue, forKey: Key.netThreshold); changed() }
    }

    /// Total CPU% of a watched process subtree that counts as "working"
    /// (covers local tool runs like test suites that make no network calls).
    var cpuThresholdPercent: Double {
        get { defaults.double(forKey: Key.cpuThreshold) }
        set { defaults.set(newValue, forKey: Key.cpuThreshold); changed() }
    }

    /// Case-insensitive substrings matched against each process's full command
    /// line. A process counts as an agent if it matches *any* pattern.
    var watchPatterns: [String] {
        get { defaults.stringArray(forKey: Key.watchPatterns) ?? ["claude"] }
        set { defaults.set(newValue, forKey: Key.watchPatterns); changed() }
    }

    /// Substrings that exclude a process from agent detection (see defaultExcludes).
    var watchExcludes: [String] {
        get { defaults.stringArray(forKey: Key.watchExcludes) ?? Preferences.defaultExcludes }
        set { defaults.set(newValue, forKey: Key.watchExcludes); changed() }
    }

    func isWatching(_ pattern: String) -> Bool {
        watchPatterns.contains { $0.caseInsensitiveCompare(pattern) == .orderedSame }
    }

    func setWatching(_ pattern: String, _ on: Bool) {
        var list = watchPatterns
        list.removeAll { $0.caseInsensitiveCompare(pattern) == .orderedSame }
        if on { list.append(pattern) }
        watchPatterns = list
    }

    /// Automatically stop other keep-awake tools (caffeinate, DIY scripts) that
    /// are redundant once Vigil is managing sleep. Off by default.
    var autoCleanRedundant: Bool {
        get { defaults.bool(forKey: Key.autoCleanRedundant) }
        set { defaults.set(newValue, forKey: Key.autoCleanRedundant); changed() }
    }

    /// Read Claude transcripts (~/.claude/projects) to detect mid-turn sessions —
    /// more precise than network/CPU for Claude. On by default.
    var semanticDetection: Bool {
        get { defaults.bool(forKey: Key.semanticDetection) }
        set { defaults.set(newValue, forKey: Key.semanticDetection); changed() }
    }

    /// Ground-truth detection via Claude Code hooks (installs a tiny hook into
    /// ~/.claude/settings.json so Claude itself reports turn start/end).
    var hooksEnabled: Bool {
        get { defaults.bool(forKey: Key.hooksEnabled) }
        set { defaults.set(newValue, forKey: Key.hooksEnabled); changed() }
    }

    /// How long a GUI agent (Claude Desktop & co) stays "working" after its last
    /// sustained network burst — bridges quiet thinking/tool gaps between streams.
    var guiBurstWindowSeconds: TimeInterval {
        get { defaults.double(forKey: Key.guiBurstWindow) }
        set { defaults.set(newValue, forKey: Key.guiBurstWindow); changed() }
    }

    /// First-run onboarding shown?
    var didOnboard: Bool {
        get { defaults.bool(forKey: Key.didOnboard) }
        set { defaults.set(newValue, forKey: Key.didOnboard) }
    }

    /// Set once the user explicitly turns OFF Launch at Login, so we don't keep
    /// re-enabling it. Default false → Vigil enables itself at login out of the box.
    var loginItemUserDisabled: Bool {
        get { defaults.bool(forKey: Key.loginItemUserDisabled) }
        set { defaults.set(newValue, forKey: Key.loginItemUserDisabled) }
    }
}

extension Notification.Name {
    static let vigilPreferencesChanged = Notification.Name("vigilPreferencesChanged")
    static let vigilStateChanged = Notification.Name("vigilStateChanged")
}
