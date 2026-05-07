Status: DONE
DTG: 20260419T000000Z
Owner: Copilot
Note: Hook-driven tmux integration for Claude Code.

# claude-tmux

## Summary

claude-tmux wires Claude Code hook events into tmux so each Claude window shows live task state, permission prompts, session completion, and stopped-session history without requiring the user to inspect every window manually.

## Delivered scope

- Hook scripts update tmux window titles for boot, task progress, AskUser waits, permission prompts, idle prompts, subagent return, and stop.
- Session state persists under `~/.local/state/claude-tmux/` by default and can be overridden with `CLAUDE_TMUX_STATE_DIR`.
- `setup.sh` provides the install, uninstall, doctor, and selftest lifecycle commands.
- `claude-window-summary` and `claude-window-pane` provide fuzzy navigation across Claude windows and tmux panes.
- `claude-window-aggregate` emits a compact `status-right` summary and `claude-tmux-log` exposes recent stop activity.

## Key invariants

- Every script sources the shared lib via `source "${BASH_SOURCE[0]%/*}/claude-window-lib"`; no hook script hardcodes an install path.
- The state directory is resolved only through `cw_state_dir()`.
- Window state keys are session-qualified: `claude-window-s${session_id_digits}_w${window_id_digits}`.
- Stopped-session history survives until picker cleanup or age-based garbage collection removes it.

## Verification

- `tests/smoke.sh` covers hook behavior, picker cleanup, stopped-session GC, aggregate output, AppleScript notification delivery, and counter clamping.
- `tests/install-uninstall.sh` covers install reversal and Claude hooks wiring.
- CI runs ShellCheck plus both harnesses from `.github/workflows/shellcheck.yml`.

## Resolved questions

- Keep state under XDG state home, not `$TMPDIR`, so stopped-session history and logs survive reboots.
- Keep Linux desktop notifications out of scope; use the `■` title and activity log as the primary stop signal.
- Use `prefix+f` for the session picker even though it overrides oh-my-tmux's default find-window binding.
