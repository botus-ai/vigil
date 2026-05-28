# Changelog

## 1.0.1 — 2026-05-28

- **Fix lid-closed reliability:** disable App Nap (`LSAppNapIsDisabled`) and hold a
  `ProcessInfo` activity while keeping awake, so the heartbeat never goes stale when the
  lid is closed. Previously App Nap could throttle the polling timer, the clamshell helper
  would see a stale heartbeat, and the Mac would sleep mid-task on lid close.

## 1.0.0 — 2026-05-28

First public release.

- Automatic detection of active AI-agent sessions (Claude Code, Claude VS Code extension,
  Claude Desktop; opt-in presets for Cursor, Codex, Gemini CLI, aider, Copilot CLI, Ollama).
- Semantic detection for Claude via `~/.claude/projects` transcripts (mid-turn vs finished).
- Per-session evaluation (network throughput + process-subtree CPU) so idle/leftover
  sessions never falsely keep the Mac awake.
- Keeps the Mac awake only while agents work, then sleeps after a grace period.
- Lid-closed mode via a crash-safe privileged helper (`pmset disablesleep` + heartbeat watchdog).
- Cleanup of redundant `caffeinate` / DIY keep-awake tools (manual or automatic).
- Launch at Login (on by default), menu-bar-only, no telemetry.
- `--diagnose` one-shot detection snapshot for support.
