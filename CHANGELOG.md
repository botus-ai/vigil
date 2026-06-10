# Changelog

## 1.1.1 — 2026-06-10

**Claude Desktop (and other GUI agents) now detected properly.** Hooks cover
Claude Code, but Desktop has no hooks and relied on the network heuristic, which
dropped below threshold during thinking/tool pauses between streams — so the Mac
could sleep mid-task. GUI apps now get:

- a **streaming burst window**: two consecutive over-threshold samples open a
  ~5-minute "working" window that bridges quiet gaps between bursts (a single
  telemetry blip opens nothing);
- **tool CPU**: CPU of non-bundle child processes (bash/python the agent spawned)
  counts as work — the Electron UI's own ~10% idle CPU still doesn't.

Verified live: idle Desktop stays idle; a streaming GUI agent engages within
~15 s and stays engaged through pauses. Tunable via `guiBurstWindowSeconds`.

## 1.1.0 — 2026-06-10

**Detection rebuilt on ground truth.** After repeated reports of both failure
modes (sleeps mid-task / won't sleep after), the root problem was the approach:
guessing agent state from transcript formats and CPU/network thresholds is
inherently fragile. Vigil now installs a tiny **Claude Code hook** (merged into
`~/.claude/settings.json` with a one-time backup; removable from the menu), so
Claude itself reports session state the instant it changes:

- `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → session is **working**
- `Notification` (permission prompt / waiting for input) → **a human is needed**
  — the Mac may sleep instead of staying awake at a forgotten permission dialog
- `Stop` / `SessionEnd` → **turn over** — sleep follows after the short grace

No more format guessing, no thresholds, no polling lag for Claude Code sessions.
Crash-safe: an "active" marker only counts while its claude process is alive
(and never longer than 2h without a refresh).

Also found & fixed the main "never sleeps" culprit on real hardware: **an idle
Claude Desktop window**. Its Electron helpers burn ~10% CPU just compositing the
UI, which permanently tripped the CPU heuristic. GUI apps are now judged by
sustained network only (streaming = working); CPU stays meaningful for CLI
agents. Plus: transcript detection now only covers sessions without hook
markers, and Claude Code CLI processes are dropped from the heuristic when
hooks are live.

## 1.0.5 — 2026-06-03

- **No more confusing/flickering agent count.** The menu used to show "N of M
  agents working," but chats flip between mid-turn and waiting every few seconds,
  so the integer flickered and never matched what you think of as your open
  chats. The menu now shows the qualitative state — "An agent is working · rate ·
  CPU" or "No agent working — Mac can sleep" — plus live throughput/CPU as proof
  it's measuring. (Use `--diagnose` for the exact breakdown.)
- **Slow first responses no longer drop early.** A chat where you sent a message
  and the assistant is thinking for a while (before the first output) kept its
  "pending" window for only 180s; widened to 300s so a slow/long first response
  isn't read as idle.

## 1.0.4 — 2026-06-03

Fixes a confusing over-count and a streaming regression.

- **No more inflated "agents" count.** Subagent/workflow transcripts
  (`…/<session>/subagents/…`, `journal.jsonl`) are no longer counted as separate
  agents — one chat running a workflow used to show as several. Only top-level
  chat sessions count now (the parent's own transcript shows `tool_use` while its
  workflow runs, so active work is still detected; a rare >15 min workflow with
  idle subagents is covered by the CPU/network heuristic).
- **Menu shows only what's working.** The status line now reads "N chats working"
  (or "No agent working — sleep allowed") instead of "X of Y agents," since the
  count of idle open Claude windows (the "Y") was just noise.
- **Long streaming responses no longer read as idle.** A regression briefly gave a
  streaming message (`stop_reason: nil`) only a 180s window; Claude can stream a
  long answer for minutes, so it now gets the full 15-min working window like
  `tool_use`/`pause_turn`. Only genuinely terminal reasons are idle.
- Added a `VIGIL_PROJECTS_DIR` override for isolated self-tests of the detector.

## 1.0.3 — 2026-06-02

Definitive reliability pass after a report of two opposite intermittent failures —
the Mac sleeping on lid-close mid-task, *and* not sleeping after a session ended.
Root-caused both from the user's actual power logs and transcripts.

- **Semantic detector was blind (caused sleep-on-close).** Claude Code transcripts end
  most lines with metadata records (`mode`, `ai-title`, …); the old detector's skip-list
  missed `mode`, so during a quiet moment (model thinking, low CPU/network) it read
  "idle," dropped the assertion, and the Mac clamshell-slept mid-task. Rewrote it to scan
  for the last real `user`/`assistant` turn and ignore *all* metadata (robust to unknown
  types).
- **Staleness judged by the wrong clock (caused won't-sleep).** Mid-turn/pending state was
  aged by the file's mtime, which trailing metadata writes refresh without advancing the
  conversation — so finished/stale sessions looked "busy" indefinitely. Now every busy
  decision uses the *record's own* ISO-8601 timestamp. Terminal stop reasons
  (`end_turn`/`stop_sequence`/`max_tokens`/`refusal`) are idle; unknown reasons bias to busy.
- **Lid-closed helper latency 15s → ~2s.** The heartbeat was written atomically (which
  breaks launchd `WatchPaths`) and the daemon polled every 15s — the lid-close race window.
  Now the heartbeat is written in place and the helper is a reliable long-running 2s loop
  (`KeepAlive`, no `WatchPaths`/`StartInterval`); still fails safe (restores sleep ~30s
  after Vigil stops).
- Grace 300s → 120s (semantic now reliably bridges pauses, so the idle tail can be shorter).
- Detector exposes semantic vs heuristic signals separately; engage is immediate on the
  reliable semantic signal and debounced only for the noisy CPU/network heuristic.

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
