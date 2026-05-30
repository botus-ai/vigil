# Changelog

## 1.0.2 — 2026-05-30

Major reliability pass after a report of the Mac sleeping / showing a lock screen
while agents were running. Root-caused two distinct problems and hardened detection.

- **Display no longer sleeps/locks while keeping awake.** `keepDisplayAwake` now
  defaults ON and the display assertion is held for the *whole* engaged window (forced
  in Keep Awake mode). Previously only system sleep was prevented, so the screen still
  slept at `displaysleep` (3 min) and locked — the system was awake and the agent ran,
  but it *looked* broken.
- **Automatic mode no longer sleeps a working agent.** The engage decision now honours
  the live work signal (`isActive`) instead of only a decaying timestamp, so a mid-turn
  agent in a quiet pause is never released; grace raised 120s → 300s for the tail.
- **Detection precision (prevents "never sleeps").** Added a `watchExcludes` list so
  `claude`-named background tooling (vault sync, claude-mem, chat-auditor, this app's
  helper) is no longer mistaken for a working agent, plus a 2-poll debounce so a single
  CPU blip can't arm a long hold.
- **Local-model detection.** Network sampling now includes loopback/LAN traffic, so
  agents talking to a local model server (e.g. ollama on 127.0.0.1) register activity.
- **Long quiet tools.** Removed the 180s semantic "zombie" cutoff; a mid-turn session
  stays detected for the full 15-min window, covering long builds/tests/thinking pauses.
- **Wake recovery.** On `NSWorkspace.didWakeNotification` Vigil re-acquires its
  assertions and resets the grace window so a still-running agent is re-protected.
- **Honesty:** onboarding now explains that closing the lid always locks the screen
  (macOS security) — the agent keeps running; that's expected, not a Vigil failure.

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
