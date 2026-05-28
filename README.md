<div align="center">

<img src=".github/social-preview.png" alt="Vigil" width="640">

# Vigil

**Your Mac stays awake while your AI agents work — and sleeps when they don't.**

[![build](https://github.com/botus-ai/vigil/actions/workflows/build.yml/badge.svg)](https://github.com/botus-ai/vigil/actions/workflows/build.yml)
[![license](https://img.shields.io/github/license/botus-ai/vigil)](LICENSE)
![platform](https://img.shields.io/badge/macOS-13%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-ready-black)
[![stars](https://img.shields.io/github/stars/botus-ai/vigil?style=social)](https://github.com/botus-ai/vigil/stargazers)

</div>

Vigil is a tiny macOS menu-bar app for developers who run AI coding agents. Unlike
Amphetamine or Caffeine, **there's no switch to flip.** Vigil detects active
**Claude Code, Cursor, Codex, aider** and other agent sessions and keeps your Mac awake
*only while they're actually working* — even with the **lid closed**. The moment your
agents finish, your Mac sleeps and saves battery.

Close the lid and walk away. Your agent keeps running. When it's done, the Mac sleeps.

> Ever started a long agent task, closed the laptop, and come back to find it slept and
> killed your run? Or left Amphetamine on all night by accident? Vigil fixes both.

## Why Vigil

Running long agent tasks means babysitting Amphetamine: turn it on before you start,
remember to turn it off after. Forget, and your Mac never sleeps. Vigil removes the toggle
entirely — it's automatic, and it's accurate.

| | Vigil | Amphetamine / Caffeine | KeepingYouAwake |
|---|:---:|:---:|:---:|
| Keeps Mac awake | ✅ | ✅ | ✅ |
| **Automatic — no manual toggle** | ✅ | ⚠️ app-trigger only | ❌ |
| **Knows when an AI agent is *working*** | ✅ | ❌ | ❌ |
| Reads Claude transcript state (semantic) | ✅ | ❌ | ❌ |
| Sleeps automatically when agents stop | ✅ | ❌ | ❌ |
| **Lid-closed mode (battery, no display)** | ✅ | ✅ (manual) | ❌ |
| Stops redundant `caffeinate` for you | ✅ | ❌ | ❌ |
| Fully local, no telemetry | ✅ | ✅ | ✅ |
| Price | Free / Pro | Free | Free |

## Features

- 🧠 **Automatic agent detection.** Watches for Claude Code, the Claude VS Code extension,
  Claude Desktop, and (opt-in) Cursor, Codex, Gemini CLI, aider, Copilot CLI, Ollama.
- 🎯 **Semantic detection for Claude.** Reads `~/.claude/projects` to know when a session
  is *mid-turn* vs finished — precise even during quiet pauses between tool calls.
- 💤 **Sleeps when idle.** Releases the moment your agents stop, after a short grace period.
- 🔒 **Lid-closed mode.** Keep agents running with the laptop shut (battery, no external
  display) — backed by a crash-safe helper that always restores normal sleep.
- 🧹 **Cleans up after itself.** Finds and stops redundant `caffeinate` / DIY keep-awake
  scripts so Vigil is the single source of truth.
- 👀 **Honest status.** The menu shows "X of Y agents working", live throughput and CPU.
- 🪶 **Tiny & private.** Menu-bar only, no Dock icon, no accounts, no network calls.

## Install

**Download (recommended)** — grab the latest `Vigil.dmg` from
[Releases](https://github.com/botus-ai/vigil/releases), drag **Vigil** to Applications,
and launch it. (Until notarized builds land, right-click the app → **Open** on first run.)

**Build from source** — needs the Swift toolchain (Xcode or Command Line Tools), no Xcode
project required:

```bash
git clone https://github.com/botus-ai/vigil.git
cd vigil
./scripts/build.sh
open build/Vigil.app
```

_Homebrew cask: coming soon._

## Usage

Click the menu-bar eye icon:

- **Automatic** — keep awake only while an AI agent is working (the default).
- **Keep Awake** / **Off** — classic manual modes.
- **Watch for…** — pick which AI tools to track.
- **Semantic detection** — read Claude transcripts for precise mid-turn detection.
- **Keep awake with lid closed** — one-time admin approval installs the helper.
- **Stop other keep-awake tools** — quit redundant `caffeinate` / scripts.
- **Launch at Login** — on by default.

Icons: `eye` = idle · `eye.fill` = keeping awake · `bolt.fill` = force-awake · `moon.zzz` = off.

## How it works

Each agent session is evaluated **individually** (so a crowd of idle/leftover sessions can
never falsely keep the Mac awake). A session is *working* when any of these is true:

1. **Semantic state (Claude)** — its transcript shows it's mid-turn (`stop_reason != end_turn`).
2. **API throughput** — sustained network traffic (universal fallback for any tool).
3. **Subtree CPU** — the process *and its children* are busy (catches long local test/build runs).

Vigil holds an IOKit power assertion while any agent works (lid open), plus a grace period.
For **lid-closed**, power assertions don't help — macOS sleeps on lid-close regardless — so
Vigil uses the documented `pmset disablesleep` flag via a small privileged helper. The app
writes a **heartbeat**; the helper disables lid-close sleep only while that heartbeat is
fresh, and **automatically restores normal sleep within ~30s** if Vigil ever stops. Your
Mac can't get stuck awake.

## Privacy

Everything runs locally. Vigil reads process/network *counters* (via `ps`/`nettop`) and,
optionally, your local Claude transcript *state* — never their contents. It makes **no
network connections of its own**. No analytics, no accounts. See [PRIVACY.md](PRIVACY.md).

## Support this project ☕

Vigil is free and open source. If it saves your overnight runs, consider supporting it:

- [Buy Me a Coffee](https://www.buymeacoffee.com/degusto_ai)
- [Ko-fi](https://ko-fi.com/degusto_ai)
- ⭐ **Star the repo** — it genuinely helps others find it.

## Contributing

Issues and PRs welcome. Build with `./scripts/build.sh`; `Vigil --diagnose` prints a
one-shot detection snapshot for debugging.

## Author

Built by **[@degusto_ai](https://t.me/degusto_ai)**. Follow for more AI-dev tooling.

## License

[MIT](LICENSE) © 2026 botus-ai (@degusto_ai)
