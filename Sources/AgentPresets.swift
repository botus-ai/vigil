import Foundation

struct AgentPreset {
    let name: String
    let pattern: String
}

/// Known AI tools Vigil can watch for. The pattern is matched (case-insensitive)
/// against each process's full command line, so it works whether the tool is the
/// executable name or a CLI subcommand/argument.
enum AgentPresets {
    static let all: [AgentPreset] = [
        AgentPreset(name: "Claude (Code, VS Code, Desktop)", pattern: "claude"),
        AgentPreset(name: "OpenAI Codex CLI", pattern: "codex"),
        AgentPreset(name: "Gemini CLI", pattern: "gemini"),
        AgentPreset(name: "aider", pattern: "aider"),
        AgentPreset(name: "Cursor Agent", pattern: "cursor-agent"),
        AgentPreset(name: "GitHub Copilot CLI", pattern: "copilot"),
        AgentPreset(name: "Ollama", pattern: "ollama"),
    ]
}
