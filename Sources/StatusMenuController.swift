import AppKit

/// The menu bar item: status icon, status text, mode switch, and toggles.
final class StatusMenuController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: AppController

    private let statusTitleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let agentsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let modeAutoItem = NSMenuItem(title: "Automatic", action: #selector(selectMode(_:)), keyEquivalent: "")
    private let modeAwakeItem = NSMenuItem(title: "Keep Awake", action: #selector(selectMode(_:)), keyEquivalent: "")
    private let modeOffItem = NSMenuItem(title: "Off", action: #selector(selectMode(_:)), keyEquivalent: "")
    private let displayItem = NSMenuItem(title: "Keep display awake too", action: #selector(toggleDisplay), keyEquivalent: "")
    private let lidItem = NSMenuItem(title: "Keep awake with lid closed", action: #selector(toggleLid), keyEquivalent: "")
    private let removeHelperItem = NSMenuItem(title: "Remove lid-closed helper…", action: #selector(removeHelper), keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunch), keyEquivalent: "")
    private let watchItem = NSMenuItem(title: "Watch for…", action: nil, keyEquivalent: "")
    private let semanticItem = NSMenuItem(title: "Semantic detection (Claude transcripts)", action: #selector(toggleSemantic), keyEquivalent: "")
    private let cleanupItem = NSMenuItem(title: "Stop other keep-awake tools", action: #selector(runCleanup), keyEquivalent: "")
    private let autoCleanItem = NSMenuItem(title: "Auto-stop redundant keep-awake tools", action: #selector(toggleAutoClean), keyEquivalent: "")
    private var presetItems: [(item: NSMenuItem, pattern: String)] = []

    init(controller: AppController) {
        self.controller = controller
        super.init()
        buildMenu()
        controller.onStatusChange = { [weak self] status in self?.render(status) }
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusTitleItem.isEnabled = false
        agentsItem.isEnabled = false
        menu.addItem(statusTitleItem)
        menu.addItem(agentsItem)
        menu.addItem(.separator())

        let modeHeader = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        modeAutoItem.target = self;  modeAutoItem.tag = 0
        modeAwakeItem.target = self; modeAwakeItem.tag = 1
        modeOffItem.target = self;   modeOffItem.tag = 2
        modeAutoItem.toolTip = "Keep awake only while an AI agent is working."
        modeAwakeItem.toolTip = "Always keep awake until you turn it off."
        modeOffItem.toolTip = "Never prevent sleep."
        menu.addItem(modeAutoItem)
        menu.addItem(modeAwakeItem)
        menu.addItem(modeOffItem)
        menu.addItem(.separator())

        // "Watch for…" submenu of AI-tool presets.
        let watchSub = NSMenu()
        for preset in AgentPresets.all {
            let item = NSMenuItem(title: preset.name, action: #selector(toggleWatch(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.pattern
            watchSub.addItem(item)
            presetItems.append((item, preset.pattern))
        }
        watchItem.submenu = watchSub
        menu.addItem(watchItem)
        semanticItem.target = self
        semanticItem.toolTip = "Read ~/.claude/projects to know when a Claude session is mid-turn."
        menu.addItem(semanticItem)
        menu.addItem(.separator())

        displayItem.target = self
        lidItem.target = self
        removeHelperItem.target = self
        menu.addItem(displayItem)
        menu.addItem(lidItem)
        menu.addItem(removeHelperItem)
        menu.addItem(.separator())

        cleanupItem.target = self
        autoCleanItem.target = self
        cleanupItem.toolTip = "Stop caffeinate and DIY keep-awake scripts — Vigil manages sleep now."
        menu.addItem(cleanupItem)
        menu.addItem(autoCleanItem)
        menu.addItem(.separator())

        launchItem.target = self
        menu.addItem(launchItem)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Vigil", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Vigil", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Rendering

    private func render(_ status: VigilStatus) {
        // Icon
        let symbol: String
        switch status.mode {
        case .off:       symbol = "moon.zzz"
        case .keepAwake: symbol = "bolt.fill"
        case .automatic: symbol = status.holdingAwake ? "eye.fill" : "eye"
        }
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vigil")
            image?.isTemplate = true
            button.image = image
        }

        // Status line
        switch status.mode {
        case .off:
            statusTitleItem.title = "Sleep allowed"
        case .keepAwake:
            statusTitleItem.title = status.lidClosedActive ? "Keeping awake (lid closed ok)" : "Keeping awake"
        case .automatic:
            statusTitleItem.title = status.holdingAwake
                ? (status.lidClosedActive ? "Active · keeping awake (lid ok)" : "Active · keeping awake")
                : "Idle · sleep allowed"
        }
        if status.degraded {
            statusTitleItem.title = "⚠︎ macOS refused the sleep assertion — screen may sleep"
        }

        // Agents line: "X of Y agents working" so leftover idle sessions are clear.
        let snap = status.snapshot
        if snap.agentCount == 0 {
            agentsItem.title = "No agents detected"
        } else if snap.activeAgentCount == 0 {
            agentsItem.title = "\(snap.agentCount) agent\(snap.agentCount == 1 ? "" : "s") · idle"
        } else {
            agentsItem.title = "\(snap.activeAgentCount) of \(snap.agentCount) agents working · "
                + "\(humanRate(snap.netBytesPerSec)) · \(String(format: "%.0f%% CPU", snap.cpuPercent))"
        }

        // Mode radios
        modeAutoItem.state  = (status.mode == .automatic) ? .on : .off
        modeAwakeItem.state = (status.mode == .keepAwake) ? .on : .off
        modeOffItem.state   = (status.mode == .off) ? .on : .off

        // Watch-for presets
        let prefs = Preferences.shared
        for (item, pattern) in presetItems {
            item.state = prefs.isWatching(pattern) ? .on : .off
        }
        semanticItem.state = prefs.semanticDetection ? .on : .off

        // Toggles
        displayItem.state = prefs.keepDisplayAwake ? .on : .off
        lidItem.state = prefs.lidClosedMode ? .on : .off
        removeHelperItem.isEnabled = controller.clamshell.isHelperInstalled
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off

        // Cleanup
        autoCleanItem.state = prefs.autoCleanRedundant ? .on : .off
        if status.redundantCount > 0 {
            cleanupItem.title = "Stop other keep-awake tools (\(status.redundantCount))…"
            cleanupItem.isEnabled = true
        } else {
            cleanupItem.title = "Stop other keep-awake tools"
            cleanupItem.isEnabled = false
        }
    }

    private func humanRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
    }

    // MARK: - Actions

    @objc private func selectMode(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: Preferences.shared.mode = .keepAwake
        case 2: Preferences.shared.mode = .off
        default: Preferences.shared.mode = .automatic
        }
    }

    @objc private func toggleDisplay() {
        Preferences.shared.keepDisplayAwake.toggle()
    }

    @objc private func toggleWatch(_ sender: NSMenuItem) {
        guard let pattern = sender.representedObject as? String else { return }
        let prefs = Preferences.shared
        prefs.setWatching(pattern, !prefs.isWatching(pattern))
    }

    @objc private func toggleAutoClean() {
        Preferences.shared.autoCleanRedundant.toggle()
    }

    @objc private func toggleSemantic() {
        Preferences.shared.semanticDetection.toggle()
    }

    @objc private func runCleanup() {
        let found = controller.cleanup.find()
        guard !found.isEmpty else { return }
        let list = found.map { "• pid \($0.pid) — \($0.reason)" }.joined(separator: "\n")
        let a = NSAlert()
        a.messageText = "Stop \(found.count) other keep-awake tool\(found.count == 1 ? "" : "s")?"
        a.informativeText = """
        Vigil is managing sleep now, so these are redundant and will be asked to quit:

        \(list)
        """
        a.addButton(withTitle: "Stop Them")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .informational
        if a.runModal() == .alertFirstButtonReturn {
            controller.cleanup.stop(found)
            controller.refreshStatus()
        }
    }

    @objc private func toggleLaunch() {
        let enable = !LaunchAtLogin.isEnabled
        LaunchAtLogin.set(enable)
        Preferences.shared.loginItemUserDisabled = !enable
        controller.refreshStatus()
    }

    @objc private func toggleLid() {
        let prefs = Preferences.shared
        if prefs.lidClosedMode {
            prefs.lidClosedMode = false
            return
        }
        if controller.clamshell.isHelperInstalled {
            prefs.lidClosedMode = true
            return
        }
        guard confirmInstall() else { return }
        installLidHelper()
    }

    private func installLidHelper() {
        controller.clamshell.installHelper { [weak self] result in
            switch result {
            case .success:
                Preferences.shared.lidClosedMode = true
            case .failure(let error):
                self?.alert(title: "Couldn’t install the lid-closed helper",
                            text: error.localizedDescription)
            }
            self?.controller.refreshStatus()
        }
    }

    /// First-run welcome. Vigil already works automatically; this only offers the
    /// one privileged step (lid-closed mode) so the user isn't left guessing.
    func runOnboarding() {
        let a = NSAlert()
        a.messageText = "Vigil is running"
        a.informativeText = """
        Vigil now lives in your menu bar (the eye icon) and starts at login. It keeps your \
        Mac awake automatically while an AI agent is working, and lets it sleep when they \
        stop — there's nothing to toggle.

        In Automatic mode, Vigil lets the Mac sleep (and lock as usual) a few minutes after \
        your agents stop — the eye icon shows when it's actively holding awake.

        One thing to know: when you CLOSE the lid, macOS always locks the screen — that's a \
        security feature Vigil can't (and shouldn't) override. Your agent keeps running; \
        you'll just see the lock screen when you reopen. That's expected, not a failure.

        Want agents to keep running with the lid CLOSED? That needs a one-time administrator \
        approval to install a small helper. (You can also enable this later from the menu.)
        """
        a.addButton(withTitle: "Enable Lid-Closed Mode…")
        a.addButton(withTitle: "Not Now")
        a.alertStyle = .informational
        if a.runModal() == .alertFirstButtonReturn {
            if controller.clamshell.isHelperInstalled {
                Preferences.shared.lidClosedMode = true
                controller.refreshStatus()
            } else {
                installLidHelper()
            }
        }
    }

    @objc private func removeHelper() {
        controller.clamshell.uninstallHelper { [weak self] result in
            if case .failure(let error) = result {
                self?.alert(title: "Couldn’t remove the helper", text: error.localizedDescription)
            }
            Preferences.shared.lidClosedMode = false
            self?.controller.refreshStatus()
        }
    }

    private func confirmInstall() -> Bool {
        let a = NSAlert()
        a.messageText = "Enable lid-closed mode?"
        a.informativeText = """
        macOS sleeps when you close the lid, and app-level settings can’t prevent that. \
        Vigil will install a small background helper (one administrator prompt) that disables \
        lid-close sleep only while an agent is working. If Vigil quits or crashes, the helper \
        automatically restores normal sleep within 15 seconds.
        """
        a.addButton(withTitle: "Install Helper…")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .informational
        return a.runModal() == .alertFirstButtonReturn
    }

    private func alert(title: String, text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .warning
        a.runModal()
    }

    @objc private func showAbout() {
        let a = NSAlert()
        a.messageText = "Vigil 1.0"
        a.informativeText = """
        Keep your Mac awake while your AI agents work — and let it sleep when they don’t.

        Vigil watches for active Claude sessions (Claude Code in the terminal, the VS Code \
        extension, and Claude Desktop) and prevents sleep only while they’re working. \
        Turn on “Keep awake with lid closed” to keep agents running with the lid shut.
        """
        a.addButton(withTitle: "OK")
        a.alertStyle = .informational
        a.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
