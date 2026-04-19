# Changelog

All notable changes to claude-tmux follow this file. Format loosely based on
[Keep a Changelog](https://keepachangelog.com/). Dates are UTC.

## [Unreleased]

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

### Changed
- `claude-window-aggregate` output now separates tokens with a space (`1▶ 1✓ 1■ `), matching the documented example in README/HUMANS.

### Fixed
- Counter never goes negative in the tab title. `TaskUpdate(deleted)` with no prior `TaskCreate` is now a no-op; `deleted` and `completed` are clamped at their caps; the all-deleted cleanup uses `-ge` instead of `-eq` so stale `deleted > total` state self-heals on the next event. `cw_read_state` clamps `active` at 0 as a last-resort guard.

### Removed
- `install.sh` and `uninstall.sh` — consolidated into `setup.sh {install|uninstall}`. No shims are shipped; invocations in existing scripts or muscle memory must switch to the new command.
- Linux `notify-send` desktop-notification path on Stop. D-Bus discovery was fragile across Wayland, non-systemd distros, and SSH-remote tmux. The `■` tab symbol and activity-log entry remain the primary Stop signal; macOS `osascript` is retained.

## [0.1.0] — 2026-04-19

Initial implementation.

### Added
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

### Security
- `claude-window-reset` builds the macOS stop notification via AppleScript
  `system attribute` instead of string interpolation so labels containing
  `"` or `\` cannot escape the script literal.

[Unreleased]: https://github.com/Rethunk-AI/claude-tmux/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Rethunk-AI/claude-tmux/releases/tag/v0.1.0
