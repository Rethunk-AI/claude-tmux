# claude-tmux — End-user guide

Hook-driven tmux integration for Claude Code. Surfaces agent state in window tab titles, rings an audible bell on permission prompts, and provides a fuzzy session picker.

For LLM/developer onboarding and internals, see [`AGENTS.md`](./AGENTS.md).

## Prerequisites

- **tmux ≥ 3.2** (`display-popup` required for session picker)
- **bash ≥ 4.0** (associative arrays)
- **jq** — hooks merge and detection in `install.sh`
- **fzf** — session and pane pickers
- **Claude Code CLI** — installed and in `PATH`

Optional:
- `notify-send` (Linux) — desktop notification on session stop
- Nerd Font — Powerline separators in tmux status bar
- oh-my-bash — automatic plugin discovery (install.sh handles both)

## Install

```bash
git clone https://github.com/Rethunk-AI/claude-tmux.git
cd claude-tmux
./install.sh
```

`install.sh` will:
1. Symlink all `bin/` scripts to `~/.local/bin/` (idempotent)
2. Create `~/.local/state/claude-tmux/` for persistent state + logs
3. Patch `~/.claude/settings.json` with the Claude Code hooks block (skipped if already present; merges per-event if a foreign hooks block exists)
4. Wire `shell/claude-label.bash` as an oh-my-bash plugin (if `~/.oh-my-bash` exists), or print a `source` line for `.bashrc`/`.zshrc`
5. Print tmux config instructions

## Tmux config

**Plain tmux** — add to `~/.tmux.conf`:
```
source-file /path/to/claude-tmux/tmux/settings.conf
source-file /path/to/claude-tmux/tmux/bindings.conf
source-file /path/to/claude-tmux/tmux/plain-tmux.conf
```

**oh-my-tmux** — merge relevant sections from `tmux/oh-my-tmux.conf`, `tmux/settings.conf`, and `tmux/bindings.conf` into `~/.tmux.conf.local`. Then `prefix+r` to reload.

## Shell integration

**oh-my-bash users:** add `claude-label` to the plugins array in `~/.bashrc` (install.sh already created the plugin symlink).

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

Log is written to `~/.local/state/claude-tmux/activity.log` on each session stop.

## Window title symbols

| Symbol | State |
|--------|-------|
| `○` | Idle / waiting for tasking |
| `▶` | Tasks in progress |
| `✓` | All tasks complete |
| `■` | Session stopped (desktop notification sent) |
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

## Uninstall

1. Remove symlinks: `rm ~/.local/bin/claude-window-* ~/.local/bin/claude-tmux-log`
2. Remove state: `rm -rf ~/.local/state/claude-tmux`
3. Remove the hooks block from `~/.claude/settings.json` (the entries with `claude-window-` in the command)
4. If using oh-my-bash: remove `~/.oh-my-bash/custom/plugins/claude-label/` and drop `claude-label` from your plugins array
5. Revert your `~/.tmux.conf` or `~/.tmux.conf.local` source lines
