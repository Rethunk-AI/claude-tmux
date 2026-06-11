# Changelog

All notable changes to claude-tmux follow this file. Format loosely based on
[Keep a Changelog](https://keepachangelog.com/). Dates are UTC.

## [Unreleased]

## [0.3.2] — 2026-06-11

### Fixed
- Shellcheck CI workflow now carries least-privilege `permissions: contents: read`, resolving three medium `actions/missing-workflow-permissions` CodeQL alerts.

## [0.3.1] — 2026-05-29

### Added
- macOS CI job (`smoke-macos`): runs the smoke and install/uninstall harnesses on `macos-latest` under the BSD userland with Homebrew bash 4+, exercising the macOS-only code paths (mkdir-based lock fallback, BSD-awk `claude-tmux-log --stats`, and the osascript notification branch) that the Linux job never covered.

### Fixed
- `claude-tmux-log --stats` used the gawk-only `asorti()` for the sessions-per-day table, which aborts under the BSD awk shipped on macOS. Replaced with a portable sort so `--stats` works on macOS.

### Changed
- `bin/*` and `tests/*.sh` shebangs changed from `#!/bin/bash` to `#!/usr/bin/env bash` so the scripts run under Homebrew bash 4+ on macOS rather than the system bash 3.2 (which lacks the associative arrays the pickers and aggregate require). `setup.sh` already used this form.

## [0.3.0] — 2026-05-29

### Added
- `SessionStart` hook wired to `claude-window-session`: shows `○` indicator immediately at session start; on `resume`/`compact` restores the correct `▶`/`○` title without clobbering active task state.
- `PreCompact` hook wired to `claude-window-compact`: sets transient `⟳` window title while context compaction runs; clears back to normal progress/idle title on the next tool call.
- `⟳` window title symbol for context compaction in progress.
- Cross-platform desktop notification on session stop via `cw_notify`: macOS uses `osascript` (unchanged); Linux, \*BSD, and SSH sessions now use an OSC 777 terminal escape written to the pane TTY. Restores Linux notification capability removed in 0.1.0; the OSC mechanism works over SSH where the prior `notify-send`/D-Bus approach failed. Caveat: OSC 9/777 support is terminal-dependent and silently ignored when absent; inside tmux, `set -g allow-passthrough on` is required.
- `claude-tmux-log --stats` / `-s`: prints an activity summary (total sessions, date range, sessions per UTC day, top labels, top workspaces, aggregate task completion rate) instead of tailing the log.
- `claude-tmux-doctor` now checks activity-log health (size, entry count, rotation-backup presence, over-cap warning) and warns about stale `.stopped` sentinels older than `CLAUDE_TMUX_STOPPED_MAX_DAYS` that the picker will GC.
- `cw_sanitize` helper in the shared lib: strips control characters from strings for display/TSV hygiene (defense-in-depth; tmux ≥ 3.2 single-pass expansion already prevents `#(...)` execution).
- `cw_notify` helper in the shared lib: encapsulates the cross-platform notification logic described above.

### Changed
- `claude-window-restore` (PostToolUse `.*`) skips the `tmux rename-window` call when the window title already matches the target, reducing title flicker on high-frequency tool events.
- Task labels are passed through `cw_sanitize` before being persisted to state files.

## [0.2.0] — 2026-05-07

### Added
- Smoke coverage for the empty, non-interactive session-picker path so CI catches regressions where stale-sentinel GC leaves no sessions.

### Changed
- Specs now use the Citadel SDD layout: active, parked, and done areas with an index, config, and completed task record for `claude-tmux`.
- `AGENTS.md` now points contributors at the canonical specs index for onboarding context.

## [0.1.0] — 2026-05-07

Initial release.

### Added
- `setup.sh` — single entrypoint replacing `install.sh` and `uninstall.sh`. Subcommands: `install`, `uninstall`, `doctor`, `selftest`, `help`.
- `bin/claude-tmux-doctor` — health check over deps, symlinks, state dir, hooks, and tmux runtime options.
- Concurrent-write safety: `cw_lock` / `cw_unlock` in the shared lib, wired into `claude-window-status` and `claude-window-reset`. Uses `flock` when present, `mkdir`-based fallback otherwise (stock macOS lacks `flock`).
- Activity log rotation on Stop: rolled to `activity.log.1` when over `CLAUDE_TMUX_LOG_MAX_BYTES` (default 1 MiB).
- Stopped-session GC in the picker: state files whose `.stopped` sentinel is older than `CLAUDE_TMUX_STOPPED_MAX_DAYS` (default 30) are swept.
- Installer: warns when `~/.tmux.conf` or `~/.tmux.conf.local` sets `bell-action` to a value other than `any`.
- Smoke coverage for the session picker, pane picker, aggregate, orphan cleanup, session-qualified key isolation, stale-sentinel GC, the macOS `osascript` path, and log rotation.
- `tests/install-uninstall.sh` harness, wired into CI.
- Requirement traceability matrix (CT1–CT29) in the spec.
- Hook-driven tmux integration for Claude Code (`bin/claude-window-*`).
  - PreToolUse: session bootup indicator (`○`), AskUserQuestion waiter (`?`).
  - PostToolUse: progress counter (`▶ N/M`, `✓ N/N`) + transient-state restore.
  - Notification: permission prompt (`!` + bell), idle prompt (`·`).
  - SubagentStop: return indicator (`↩`).
  - Stop: stopped state (`■`) + desktop notification + activity log entry.
- `prefix+f` — fuzzy session picker (`claude-window-summary`).
- `prefix+P` — fuzzy pane picker (`claude-window-pane`).
- Status-right aggregate (`claude-window-aggregate`).
- Activity log at `~/.local/state/claude-tmux/activity.log` with
  `claude-tmux-log` viewer (`-n`, `-f`).
- `claude-label` shell function (plain bash/zsh + oh-my-bash plugin).
- Install script (`install.sh`) with bash-version and dependency preflight.
- Uninstall script (`uninstall.sh`) that reverses the install steps.
- Smoke-test harness (`tests/smoke.sh`) exercising every hook against a stub
  tmux.
- CI: shellcheck over all scripts + smoke harness execution.
- Session-qualified state key (`s<sid>_w<wid>`) to prevent stale state bleed
  across tmux server restarts.
- Orphan cleanup of state files whose tmux window no longer exists.

### Changed
- `claude-window-aggregate` output now separates tokens with a space (`1▶ 1✓ 1■ `), matching the documented example in README/HUMANS.

### Fixed
- `claude-window-summary` no longer blocks on `read` when there are zero sessions (e.g. after stale-sentinel GC) unless stdin is a TTY, so smoke/CI completes.
- Counter never goes negative in the tab title. `TaskUpdate(deleted)` with no prior `TaskCreate` is now a no-op; `deleted` and `completed` are clamped at their caps; the all-deleted cleanup uses `-ge` instead of `-eq` so stale `deleted > total` state self-heals on the next event. `cw_read_state` clamps `active` at 0 as a last-resort guard.

### Removed
- `install.sh` and `uninstall.sh` — consolidated into `setup.sh {install|uninstall}`. No shims are shipped; invocations in existing scripts or muscle memory must switch to the new command.
- Linux `notify-send` desktop-notification path on Stop. D-Bus discovery was fragile across Wayland, non-systemd distros, and SSH-remote tmux. The `■` tab symbol and activity-log entry remain the primary Stop signal; macOS `osascript` is retained.

### Security
- `claude-window-reset` builds the macOS stop notification via AppleScript
  `system attribute` instead of string interpolation so labels containing
  `"` or `\` cannot escape the script literal.

[Unreleased]: https://github.com/Rethunk-AI/claude-tmux/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/Rethunk-AI/claude-tmux/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Rethunk-AI/claude-tmux/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Rethunk-AI/claude-tmux/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Rethunk-AI/claude-tmux/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Rethunk-AI/claude-tmux/releases/tag/v0.1.0
