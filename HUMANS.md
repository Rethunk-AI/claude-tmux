# claude-tmux — End-user guide

Hook-driven tmux integration for Claude Code. Surfaces agent state in window tab titles, rings an audible bell on permission prompts, and provides a fuzzy session picker.

For LLM/developer onboarding and internals, see [`AGENTS.md`](./AGENTS.md).

## Prerequisites

- **tmux ≥ 3.2** (`display-popup` required for session picker)
- **bash ≥ 4.0** (associative arrays)
- **jq** — hook JSON parsing + settings.json merge
- **fzf** — session and pane pickers
- **Claude Code CLI** — installed and in `PATH`

Optional:
- macOS `osascript` — desktop notification on session stop (macOS only)
- `flock` — advisory file locking for concurrent hooks (stock macOS lacks it; a `mkdir`-based fallback is used automatically)
- Nerd Font — Powerline separators in tmux status bar
- oh-my-bash — automatic plugin discovery (`setup.sh install` handles both)

## Install

```bash
git clone https://github.com/Rethunk-AI/claude-tmux.git
cd claude-tmux
./setup.sh install
```

`setup.sh install` will:
1. Symlink all `bin/` scripts to `~/.local/bin/` (idempotent)
2. Create `~/.local/state/claude-tmux/` for persistent state + logs
3. Patch `~/.claude/settings.json` with the Claude Code hooks block (skipped if already present; merges per-event if a foreign hooks block exists)
4. Wire `shell/claude-label.bash` as an oh-my-bash plugin (if `~/.oh-my-bash` exists), or print a `source` line for `.bashrc`/`.zshrc`
5. Print tmux config instructions

Other `setup.sh` commands: `uninstall` (reverse of install), `doctor` (health check), `selftest` (run smoke + install/uninstall harnesses).

## Tmux config

**Plain tmux** — add to `~/.tmux.conf`:
```
source-file /path/to/claude-tmux/tmux/settings.conf
source-file /path/to/claude-tmux/tmux/bindings.conf
source-file /path/to/claude-tmux/tmux/plain-tmux.conf
```

**oh-my-tmux** — merge relevant sections from `tmux/oh-my-tmux.conf`, `tmux/settings.conf`, and `tmux/bindings.conf` into `~/.tmux.conf.local`. Then `prefix+r` to reload.

## Shell integration

**oh-my-bash users:** add `claude-label` to the plugins array in `~/.bashrc` (`setup.sh install` already created the plugin symlink).

**Plain bash/zsh:** `source /path/to/claude-tmux/shell/claude-label.bash`

## Usage

### Labeling a session

Run before launching Claude Code:
```bash
claude-label ironlaw-network
claude
```

The label appears in the tab immediately (`○ ironlaw-network`) and carries through all state transitions.

To clear the label and revert to auto-derive behavior, call `claude-label` with no argument:
```bash
claude-label
```
This unsets `CLAUDE_WINDOW_LABEL` and renames the window to `○ <cwd-basename>`.

### Session picker

`prefix+f` — fuzzy picker over all Claude windows (active + recently stopped). Shows window title and working directory. Enter to switch.

### Pane picker

`prefix+P` — fuzzy picker over all tmux panes across all sessions.

### Status-right aggregate

Add to your tmux `status-right` to show a compact count of active Claude windows:
```
#(~/.local/bin/claude-window-aggregate)
```

Example output: `2▶ 1✓ 1■ ` (2 in progress, 1 complete, 1 stopped)

### Activity log

```bash
claude-tmux-log          # recent 25 sessions
claude-tmux-log -n 50   # last 50 entries
claude-tmux-log -f       # follow mode — stream new entries as sessions stop
```

Log is written to `~/.local/state/claude-tmux/activity.log` on each session stop. When it exceeds `CLAUDE_TMUX_LOG_MAX_BYTES` (default 1 MiB), it is rotated to `activity.log.1`; the prior `.1` is discarded. Set the env var in your shell rc to change the cap.

### Doctor

```bash
claude-tmux-doctor
```

Runs a health check over your install: dependency versions (bash, tmux, jq, fzf, optional `flock`), `~/.local/bin/` symlinks, state-dir permissions, expected hooks in `~/.claude/settings.json`, and required tmux runtime options. Exits non-zero if anything is broken.

## Window title symbols

| Symbol | State |
|--------|-------|
| `○` | Idle / waiting for tasking |
| `▶` | Tasks in progress |
| `✓` | All tasks complete |
| `■` | Session stopped (desktop notification sent on macOS) |
| `!` | Waiting for permission (bell rings) |
| `?` | Waiting for user input (AskUserQuestion) |
| `·` | Idle prompt shown |
| `↩` | Subagent just returned |

## Key bindings

| Key | Action |
|-----|--------|
| `prefix+f` | Session picker (Claude windows) |
| `prefix+P` | Pane picker (all panes) |

## Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_WINDOW_LABEL` | — | Session label set by `claude-label`; overrides auto-derived label |
| `CLAUDE_TMUX_STATE_DIR` | `~/.local/state/claude-tmux` | State file directory |
| `CLAUDE_TMUX_LOG_MAX_BYTES` | `1048576` (1 MiB) | Size threshold at which `activity.log` is rotated to `.1` on Stop |
| `CLAUDE_TMUX_STOPPED_MAX_DAYS` | `30` | Stopped-session entries older than this are pruned from the picker |

## State files

Session state is stored in `~/.local/state/claude-tmux/` (overridable via `CLAUDE_TMUX_STATE_DIR`), keyed by tmux session+window ID (`s<sid>_w<wid>`). State survives shell restarts and tmux detach/reattach; orphaned entries are cleaned up when the session picker opens, and stopped-session entries older than `CLAUDE_TMUX_STOPPED_MAX_DAYS` (30) are pruned on the same pass. Internals are documented in [`AGENTS.md`](./AGENTS.md).

## Further reading

- [`AGENTS.md`](./AGENTS.md) — developer/LLM onboarding, hook wiring, state-file model
- [`specs/done/claude-tmux/spec.md`](./specs/done/claude-tmux/spec.md) — full requirements, design decisions, traceability matrix
- [`CHANGELOG.md`](./CHANGELOG.md) — release notes

## Uninstall

```bash
./setup.sh uninstall
```

Reverses `setup.sh install`: drops the `~/.local/bin/` symlinks, strips `claude-window-*` hooks from `~/.claude/settings.json`, and removes the oh-my-bash plugin. It prints the remaining manual steps (state directory deletion if desired, tmux config revert, shell rc cleanup) at the end.
