# Vigil — Privacy Policy

_Last updated: 2026-05-28_

Vigil is designed to be completely private. **Everything runs locally on your Mac.**

## What Vigil does

- Reads local **process and network counters** via the system tools `ps` and `nettop`
  to detect when an AI agent is actively working. It reads *counts and CPU/throughput
  numbers* — never the contents of your network traffic.
- Optionally reads your local **Claude session transcripts** in `~/.claude/projects` to
  tell whether a session is mid-turn. Only each file's last record *type* and
  `stop_reason` are inspected; transcript contents are not stored, transmitted, or logged.
- Creates macOS **power assertions** and, if you enable lid-closed mode, toggles the local
  `pmset disablesleep` flag through a small helper that runs on your Mac.

## What Vigil does NOT do

- ❌ No network connections of its own. Vigil never phones home.
- ❌ No analytics, telemetry, crash reporting, or tracking.
- ❌ No accounts, logins, or cloud services.
- ❌ No collection, storage, or transmission of personal data.
- ❌ Nothing leaves your device.

## Permissions

- The optional **lid-closed mode** asks for administrator approval once, to install a
  background helper that can disable lid-close sleep (`pmset disablesleep`). The helper
  only toggles that system flag in response to Vigil's local heartbeat and restores normal
  sleep automatically if Vigil stops.
- **Launch at Login** uses Apple's `SMAppService` and is stored by macOS in your Login
  Items.

## Contact

Questions: <add your support email here>.
