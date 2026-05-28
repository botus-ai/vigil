import AppKit

// Hidden utility: dump the generated clamshell helper artifacts for inspection.
if let i = CommandLine.arguments.firstIndex(of: "--emit-clamshell"),
   i + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[i + 1]
    do {
        try ClamshellController().writeArtifacts(toDirectory: dir)
        print("Wrote clamshell artifacts to \(dir)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Failed: \(error)\n".utf8))
        exit(1)
    }
}

// Hidden utility: print one detection snapshot and exit (support / debugging).
if CommandLine.arguments.contains("--diagnose") {
    let s = ActivityMonitor().diagnostic()
    print("""
    agents detected : \(s.agentCount)
    agents working  : \(s.activeAgentCount)
    keeping awake?  : \(s.isActive)
    busiest agent   : \(String(format: "%.0f", s.netBytesPerSec)) B/s, \(String(format: "%.1f", s.cpuPercent))% CPU
    watch patterns  : \(Preferences.shared.watchPatterns.joined(separator: ", "))
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
