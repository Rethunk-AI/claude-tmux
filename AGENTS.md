# AGENTS.md — LLM onboarding

**claude-tmux** — hook-driven tmux integration for Claude Code. Surfaces Claude agent state in tmux window tab titles, rings an audible bell on permission prompts, and provides a fuzzy session picker across all Claude windows.

**Claude Code:** `CLAUDE.md` is a stub pointing here (edit **`AGENTS.md`**). No submodules; pure bash.

## Repo layout

```
bin/
  claude-window-lib       shared helpers (source this, don't run it)
  claude-window-init      PreToolUse: resolve window, write .cwd file
  claude-window-status    PostToolUse(TaskCreate|TaskUpdate): update progress title
  claude-window-restore   PostToolUse(.*): restore non-task title
  claude-window-notify    Notification: ring bell (macOS: also osascript)
  claude-window-subagent  SubagentStop: set ↩ title
  claude-window-ask       PreToolUse(AskUserQuestion): set ? title
  claude-window-reset     Stop: write activity log, reset title, macOS stop notification
  claude-window-aggregate reads state dir, emits compact in-progress/complete/stopped counts for status-right
  claude-window-pane      fzf pane picker across all sessions (launched by tmux binding)
  claude-window-summary   fzf session picker (launched by tmux binding)
  claude-tmux-log         tail/format ~/.local/state/claude-tmux/activity.log
shell/
  claude-label.bash       claude-label() function; also an oh-my-bash plugin
tmux/
  settings.conf           tmux options (automatic-rename on, bell-action any, etc.)
  bindings.conf           key bindings (prefix+f, prefix+P)
  plain-tmux.conf         status-right config for plain tmux
  oh-my-tmux.conf         equivalent for oh-my-tmux users
specs/
  index.md                table of record
  done/claude-tmux/       spec.md (Status: implemented)
setup.sh                  single entrypoint: install | uninstall | doctor | selftest
README.md
```

## Key invariants

- Every script in `bin/` sources the shared lib via **`source "${BASH_SOURCE[0]%/*}/claude-window-lib"`** — never hardcode a path.
- State is stored under **`~/.local/state/claude-tmux/`** (or `$CLAUDE_TMUX_STATE_DIR`). `cw_state_dir()` in the lib is the single source of truth.
- BASE key formula: **`claude-window-s${session_id_digits}_w${window_id_digits}`** (e.g. `claude-window-s0_w3`). The session_id prefix prevents stale state bleed when tmux recycles window IDs after a server restart. `cw_resolve_window()` in the lib sets both `WINDOW_ID` and `BASE`.
- `claude-window-summary` must use the identical key formula when scanning state files and mapping them to live windows via `tmux list-windows -a -F $'#{window_id}\t#{session_id}\t#{session_name}\t#{window_name}'` (tab-delimited so session / window names containing spaces parse cleanly).

## Hook events → scripts

| Claude Code event | Matcher | Script |
|-------------------|---------|--------|
| `PreToolUse` | `.*` | `claude-window-init` |
| `PreToolUse` | `AskUserQuestion` | `claude-window-ask` |
| `PostToolUse` | `TaskCreate\|TaskUpdate` | `claude-window-status` |
| `PostToolUse` | `.*` | `claude-window-restore` |
| `Notification` | — | `claude-window-notify` |
| `SubagentStop` | — | `claude-window-subagent` |
| `Stop` | — | `claude-window-reset` |

## State files

Each active window's state lives in `$(cw_state_dir)/claude-window-<key>.*`:

| Suffix | Content |
|--------|---------|
| `.cwd` | working directory when Claude started |
| `.label` | `CLAUDE_WINDOW_LABEL` value (from `claude-label`) |
| `.total` | total task count |
| `.completed` | completed task count |
| `.deleted` | deleted/N/A task count |
| `.stopped` | sentinel written on Stop; consumed by the next bootup to re-show `○` |

Activity log: `$(cw_state_dir)/activity.log` — TSV written on each `Stop`.

## Testing

Automated: `./setup.sh selftest` runs `tests/smoke.sh` (every hook against a stub tmux + picker / aggregate / orphan / AppleScript / log-rotation / stale-sentinel coverage) and `tests/install-uninstall.sh` (install reversal against a throw-away `$HOME`). CI runs both via `.github/workflows/shellcheck.yml`. Golden-path manual verify steps and commit conventions live in [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Further reading

- [`HUMANS.md`](./HUMANS.md) — end-user install/usage
- [`specs/done/claude-tmux/spec.md`](./specs/done/claude-tmux/spec.md) — requirements CT1–CT29, design decisions, traceability matrix
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — commit conventions, bash style, verify steps
