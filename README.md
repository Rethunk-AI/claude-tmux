# claude-tmux

Hook-driven tmux integration for Claude Code. Surfaces agent state in window tab titles, rings an audible bell on permission prompts, and provides a fuzzy session picker across all Claude windows.

```
▶ 2/5 ironlaw-network   ← tasks in progress (2 of 5 done)
✓ 5/5 ironlaw-network   ← all tasks complete
■ 5/5 ironlaw-network   ← session stopped (desktop notification sent on macOS)
! 2/5 ironlaw-network   ← waiting for permission (bell rings)
? 2/5 ironlaw-network   ← waiting for AskUserQuestion
· 2/5 ironlaw-network   ← idle prompt shown
↩ 2/5 ironlaw-network   ← subagent just returned
○ bastion               ← idle, no tasks
```

## Requirements

- tmux ≥ 3.2 (`display-popup`)
- bash ≥ 4.0 (associative arrays)
- `jq`, `fzf`
- Claude Code CLI

Optional: macOS (`osascript`) for stop notifications, a Nerd Font for Powerline separators. Linux has no desktop-notification path — stop state is shown via the `■` tab title and the activity log.

## Installation

```bash
git clone https://github.com/Rethunk-AI/claude-tmux.git
cd claude-tmux
./install.sh
```

`install.sh` will:
1. Symlink `bin/` scripts to `~/.local/bin/`
2. Symlink `shell/claude-label.bash` as an oh-my-bash plugin (if `~/.oh-my-bash` exists), or print a `source` line for `.bashrc`/`.zshrc`
3. Patch `~/.claude/settings.json` with the hooks block (skipped if already present)
4. Create `~/.local/state/claude-tmux/` for persistent state and logs
5. Print tmux config instructions

### Tmux config

**Plain tmux** — add to `~/.tmux.conf`:
```
source-file /path/to/claude-tmux/tmux/settings.conf
source-file /path/to/claude-tmux/tmux/bindings.conf
source-file /path/to/claude-tmux/tmux/plain-tmux.conf
```

**oh-my-tmux** — merge relevant sections from `tmux/oh-my-tmux.conf`, `tmux/settings.conf`, and `tmux/bindings.conf` into `~/.tmux.conf.local`. Then `prefix+r` to reload.

### Shell integration

oh-my-bash users: add `claude-label` to the plugins array in `~/.bashrc` (install.sh already created the plugin symlink).

Plain bash/zsh: `source /path/to/claude-tmux/shell/claude-label.bash`

## Usage

### Session labeling

Label a window before launching Claude:
```bash
claude-label ironlaw-network
claude
```

The label appears in the tab immediately (`○ ironlaw-network`) and carries through all state transitions.

### Session picker

`prefix+f` — fuzzy picker over all Claude windows (active + recently stopped). Shows window title and working directory. Enter to switch.

### Pane picker

`prefix+P` — fuzzy picker over all tmux panes across all sessions.

### Status-right aggregate

Add to tmux `status-right` to show a compact count of active Claude windows:
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

Log is written to `~/.local/state/claude-tmux/activity.log` on each Stop. Rotated to `activity.log.1` when it exceeds `CLAUDE_TMUX_LOG_MAX_BYTES` (default 1 MiB); the prior `.1` is discarded.

### Doctor

`claude-tmux-doctor` validates your installation: bash/tmux/jq/fzf versions, `flock` availability, `~/.local/bin/` symlinks, state-dir permissions, every expected hook in `~/.claude/settings.json`, and tmux runtime options (`automatic-rename on`, `bell-action any`). Exits non-zero on any FAIL.

## State files

Session state is stored in `~/.local/state/claude-tmux/` (or `$CLAUDE_TMUX_STATE_DIR` if set), keyed by tmux session+window ID. State survives shell restarts and tmux detach/reattach; orphaned entries are cleaned up automatically when the session picker opens.

## Key bindings

| Key | Action |
|-----|--------|
| `prefix+f` | Session picker (Claude windows) |
| `prefix+P` | Pane picker (all panes) |

## Window title symbols

| Symbol | State |
|--------|-------|
| `○` | Idle / waiting for tasking |
| `▶` | Tasks in progress |
| `✓` | All tasks complete |
| `■` | Session stopped |
| `!` | Waiting for permission (bell rings) |
| `?` | Waiting for user input |
| `·` | Idle prompt shown |
| `↩` | Subagent returned |

## Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_WINDOW_LABEL` | — | Session label (set by `claude-label`; overrides auto-derived label) |
| `CLAUDE_TMUX_STATE_DIR` | `~/.local/state/claude-tmux` | State file directory |
| `CLAUDE_TMUX_LOG_MAX_BYTES` | `1048576` (1 MiB) | `activity.log` is rotated to `.1` when it exceeds this size on Stop |
| `CLAUDE_TMUX_STOPPED_MAX_DAYS` | `30` | Stopped sessions older than this are pruned from the picker on next open |

## Spec

Full use case / requirements / design decisions: [`specs/done/claude-tmux/spec.md`](specs/done/claude-tmux/spec.md)
