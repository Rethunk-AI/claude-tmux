# Changelog

All notable changes to claude-tmux follow this file. Format loosely based on
[Keep a Changelog](https://keepachangelog.com/). Dates are UTC.

## [Unreleased]

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
