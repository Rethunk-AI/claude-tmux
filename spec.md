# claude-tmux

**Status:** `draft`

**Trigger:** Claude Code's hook system exposes session lifecycle events (tool calls, task tracking, permission prompts, agent stop) but provides no built-in terminal multiplexer integration. Developers running multiple concurrent Claude Code sessions in tmux have no ambient visibility into which sessions are active, blocked, or finished without manually switching to each window. This spec defines a hook-driven tmux integration that surfaces agent state in window titles, provides audible alerting for permission prompts, enables cross-session navigation, and is installable on any machine running tmux and Claude Code.

---

## System description

`claude-tmux` is a collection of bash scripts wired into Claude Code's hook system. Each hook event updates a per-window state machine stored in `$TMPDIR`, then calls `tmux rename-window` to reflect the current state in the window tab title. A shared library (`claude-window-lib`) provides common window resolution, state reading, and title generation logic to all scripts.

### State machine

Each tmux window running Claude Code transitions through the following states, reflected in the window title prefix:

| Symbol | State | Trigger |
|--------|-------|---------|
| `○` | Idle / waiting for tasking | PreToolUse bootup, CWD change, or after stop |
| `▶` | Tasks in progress | PostToolUse TaskCreate or TaskUpdate (incomplete) |
| `✓` | All tasks complete | PostToolUse TaskUpdate, all active tasks completed |
| `■` | Session stopped | Stop hook |
| `?` | Waiting for user (AskUserQuestion) | PreToolUse AskUserQuestion |
| `!` | Waiting for permission | Notification permission_prompt |
| `·` | Idle prompt shown | Notification idle_prompt |
| `↩` | Subagent returned | SubagentStop hook |

Transient states (`?`, `!`, `·`, `↩`) are cleared back to the real progress state by the PostToolUse restore hook on the next tool call.

### State persistence

Per-window state is stored as flat files in `$TMPDIR`, keyed by tmux window ID (e.g. `claude-window-3.total`). Files written:

| File | Content | Lifetime |
|------|---------|----------|
| `.cwd` | Absolute path of Claude's working directory | Created on bootup; kept after stop for session picker |
| `.total` | Total tasks created (integer) | Cleared on stop or all-deleted |
| `.completed` | Tasks that reached `completed` status | Cleared on stop |
| `.deleted` | Tasks that reached `deleted` status | Cleared on stop |
| `.label` | Session label (from env var or first task subject) | Cleared on stop |
| `.stopped` | Sentinel written on stop | Consumed on next bootup |

### Title format

- With tasks: `<symbol> <completed>/<active><label>` where `active = total - deleted` and label is prefixed with a space only when non-empty.
- Without tasks: `<symbol> <workspace>` where workspace is the basename of the stored `.cwd` path.

### Hook wiring (`~/.claude/settings.json`)

| Event | Matcher | Script |
|-------|---------|--------|
| PreToolUse | `.*` | `claude-window-init` |
| PreToolUse | `AskUserQuestion` | `claude-window-ask` |
| PostToolUse | `TaskCreate\|TaskUpdate` | `claude-window-status` |
| PostToolUse | `.*` | `claude-window-restore` |
| Stop | — | `claude-window-reset` |
| SubagentStop | — | `claude-window-subagent` |
| Notification | — | `claude-window-notify` |

Hook execution order within an event: scripts listed first run first. For PostToolUse, `claude-window-status` runs before `claude-window-restore` so the restore hook sees updated counters.

### Session labeling

`CLAUDE_WINDOW_LABEL` is an exported environment variable that overrides the auto-derived label for a session. The `claude-label <name>` shell function sets it and immediately renames the current tmux window to `○ <name>`, providing pre-session context before any tool call fires.

When `CLAUDE_WINDOW_LABEL` is unset, the label is derived from the `subject` field of the first `TaskCreate` call: lowercased, spaces replaced with hyphens, truncated to 24 characters.

The label is fixed for the session duration; subsequent `TaskCreate` calls do not overwrite it.

### Session picker

`prefix+f` opens a tmux `display-popup` running an `fzf` picker over all tmux windows that have a `.cwd` state file. This includes both active (`▶`, `✓`, `?`, `!`) and recently stopped (`■`) sessions. The picker displays the current window title alongside the abbreviated CWD (`$HOME` collapsed to `~`). Selecting an entry switches the tmux client to that window's session and focuses the window. Orphaned state files (window no longer exists in tmux) are cleaned up automatically on each picker open.

---

## Use cases

### UC1 — Monitor session state at a glance

**Actor:** Developer  
**Trigger:** One or more Claude Code sessions are running in tmux windows  
**Goal:** Know the current state of each session without switching windows  
**Flow:** Developer glances at the tmux tab bar; each window title shows the state symbol and task progress. No interaction required.  
**Success:** Title accurately reflects agent state within one hook event of any state change.

### UC2 — Get alerted when Claude needs permission

**Actor:** Developer working in a different window or application  
**Trigger:** Claude Code emits a `permission_prompt` notification  
**Goal:** Be notified immediately that Claude is blocked  
**Flow:** Hook fires, window title changes to `! N/M label`, audible bell is written to the pane's tty. Terminal emulator produces an audio alert.  
**Success:** Bell rings; window tab shows `!`; developer can respond without polling.

### UC3 — Navigate to a specific Claude session

**Actor:** Developer with multiple Claude sessions open  
**Trigger:** Developer wants to switch to a session by name or state  
**Goal:** Jump to any Claude window quickly  
**Flow:** `prefix+f` → fzf popup with all Claude windows → select → tmux switches.  
**Success:** Developer reaches target window in ≤3 keystrokes.

### UC4 — Label a session before starting work

**Actor:** Developer about to launch Claude on a specific task  
**Trigger:** Developer wants the session named meaningfully from the start  
**Flow:** `claude-label ironlaw-network` → CLAUDE_WINDOW_LABEL set, window renamed `○ ironlaw-network` → `claude` launched → all subsequent titles carry that label.  
**Success:** Label appears in tab and session picker without waiting for the first TaskCreate.

### UC5 — See completion after Claude finishes

**Actor:** Developer who left Claude running in background  
**Trigger:** Claude Code stops  
**Goal:** Know the session ended and how many tasks ran  
**Flow:** Stop hook fires → window renamed `■ N/M label` → desktop notification sent.  
**Success:** Tab shows `■`; notification shows label and task count; session remains in picker.

### UC6 — Install on a new machine

**Actor:** Developer setting up a new workstation  
**Trigger:** Developer wants the full claude-tmux system  
**Flow:** Clone repo → `./install.sh` → restart shell → add tmux config snippet → `prefix+r` in tmux.  
**Success:** All hooks active; window titles update; `prefix+f` opens picker.

---

## Requirements

### Must have

| ID | Requirement | Acceptance |
|----|-------------|------------|
| CT1 | **Shared library** — `claude-window-lib` provides `cw_resolve_window` (sets `WINDOW_ID` and `BASE` from `$TMUX_PANE` or active client), `cw_read_state` (reads all counter files into globals), `cw_title` (prints the correct `▶`/`✓` title), and `cw_workspace` (returns stored workspace name). All hook scripts source this library; none duplicate these patterns. | All 7 hook scripts contain `source .../claude-window-lib`; no script contains its own window ID resolution block. |
| CT2 | **Window title updated on every state transition** — Each hook script calls `tmux rename-window -t "$WINDOW_ID"` with the correct title for its event. Titles match the format in the State machine table above. | Manual test: create task → `▶ 0/1 label`; complete task → `✓ 1/1 label`; stop → `■ 1/1 label`; reboot Claude → `○ workspace`. |
| CT3 | **Progress counter: `completed/active`** — `active = total − deleted`. `completed` increments on TaskUpdate `completed`. `deleted` increments on TaskUpdate `deleted`. No counter increments on `in_progress` or `pending`. | Task create (total=1) → `▶ 0/1`; complete → `▶` becomes `✓ 1/1`; delete a second task → `✓ 1/1` (active drops). |
| CT4 | **Label: no trailing space when empty** — All title-generating code uses `${label:+ $label}` (or equivalent) so that sessions without a label do not have a trailing space. | `printf '▶ 0/1'` not `'▶ 0/1 '` when label is empty. |
| CT5 | **Workspace from `.cwd`, not `$PWD`** — All hooks that display a workspace name read `${BASE}.cwd` and fall back to `$PWD` only when the file is absent. `$PWD` in a hook subprocess is Claude's launch directory and does not reflect CWD changes mid-session. | Change CWD mid-session; all-tasks-deleted branch shows new workspace, not launch dir. |
| CT6 | **Bootup indicator** — `claude-window-init` shows `○ workspace` on: (a) first tool call (no `.cwd` file); (b) CWD change (`stored_cwd != $PWD`); (c) restart after stop (`.stopped` file present). Does nothing when tasks are active (`total > 0`). | Three scenarios tested manually; `○` appears exactly when expected. |
| CT7 | **All-tasks-deleted clears state** — When `deleted == total`, `claude-window-status` removes all counter files and shows `○ workspace`. Does not write `.stopped` (session is still live). | Delete all tasks → `○ workspace` appears; picker still shows window (`.cwd` intact). |
| CT8 | **Stop hook** — `claude-window-reset` on Stop: (a) shows `■ completed/active label` if `total > 0`; (b) clears all counter files; (c) keeps `.cwd`; (d) writes `.stopped`. | After stop: tab shows `■`; `.cwd` exists; `.total` absent; `.stopped` exists. |
| CT9 | **Restore hook clears transient states** — `claude-window-restore` fires on every PostToolUse and overwrites any `?`, `!`, `·`, `↩` title with the correct progress state. Exits without renaming if `.stopped` is present (defensive guard). | After `?` appears (AskUserQuestion), next tool use restores `▶`/`✓`/`○`. |
| CT10 | **Permission alert** — `claude-window-notify` on `permission_prompt`: (a) sets window title to `! completed/active label` or `! workspace`; (b) writes `\a` (BEL) to the pane's tty. No desktop notification sent. | Bell rings in terminal emulator; tab shows `!`. |
| CT11 | **Idle prompt** — `claude-window-notify` on `idle_prompt`: sets title to `· completed/active label` or `· workspace`. No bell. | Tab shows `·` when Claude enters idle prompt. |
| CT12 | **Session picker** — `claude-window-summary` lists all windows with a `.cwd` file (active + stopped). Display format: `%-36s  %s` of window title and abbreviated path (`$HOME → ~`). Enter switches tmux client to selected window. Orphaned entries (window closed) cleaned up on open. | Open picker with 3 windows (1 active, 1 stopped, 1 different CWD) → all 3 shown; select → window focused. |
| CT13 | **Session labeling** — `claude-label <name>` sets `CLAUDE_WINDOW_LABEL` and renames current tmux window to `○ <name>`. `claude-window-status` on first TaskCreate uses `CLAUDE_WINDOW_LABEL` if set, else derives from `tool_input.subject` (lowercase, hyphenated, max 24 chars). Label fixed for session duration. | `claude-label foo` → window shows `○ foo`; first task → `▶ 0/1 foo`. |
| CT14 | **Hook failure is silent** — All scripts exit 0; all `tmux rename-window` calls use `2>/dev/null \|\| true`. A missing or broken tmux session never crashes a hook script. | Kill tmux session while Claude runs → no hook error surfaced to Claude Code. |
| CT15 | **Stop notification** — On Stop with `total > 0`, sends a desktop notification: `notify-send` on Linux, `osascript` on macOS. Detected at runtime via `uname`. No notification when no tasks ran. | Stop after tasks → notification shown. Stop with no tasks → no notification. |
| CT16 | **install.sh** — Symlinks all scripts from `bin/` to `~/.local/bin/`, merges the hook block into `~/.claude/settings.json` using `jq`, and prints the tmux config snippet the user must add manually. Idempotent (safe to run twice). | Fresh system: run install.sh → hooks active after shell restart. Run again → no duplicate symlinks, no duplicate JSON keys. |

### Should have

| ID | Requirement | Acceptance |
|----|-------------|------------|
| CT17 | **oh-my-tmux window status colors** — Per-state color rules for `tmux_conf_theme_window_status_format` and `tmux_conf_theme_window_status_current_format` ship as a config snippet. Colors: `▶` blue, `✓` green, `!` red, `?` gold, `■` dark gray, `↩` lavender, `·` dim gray. | Snippet documented; colors render correctly with oh-my-tmux and a Powerline/Nerd font. |
| CT18 | **Plain tmux config variant** — A companion config file provides equivalent `set -g window-status-format` / `set -g window-status-current-format` rules for users without oh-my-tmux. | Snippet documented and tested with vanilla tmux 3.2. |
| CT19 | **Pane picker** — `prefix+P` opens a `display-popup` fzf picker over all tmux panes (`tmux list-panes -a`), showing session:window.pane, window name, current path, and running command. Enter switches to selected pane. | Open picker → all panes listed; select → pane focused. |
| CT20 | **Subagent return indicator** — `claude-window-subagent` (SubagentStop hook) sets `↩ completed/active label` briefly; cleared by next PostToolUse restore. | SubagentStop fires → `↩` appears; next tool use → previous state restored. |
| CT21 | **`claude-label` shell function ships as a standalone sourced file** — `shell/claude-label.bash` can be sourced directly from `.bashrc`/`.zshrc` without oh-my-bash. oh-my-bash users can load it as a custom plugin. | `source shell/claude-label.bash` → `claude-label` function available. |

### Nice to have

| ID | Requirement | Acceptance |
|----|-------------|------------|
| CT22 | **Status-right aggregate** — A script callable from `status-right` scans all `$TMPDIR/claude-window-*.cwd` files and emits a summary of active Claude windows (e.g. `2▶ 1✓`) for the tmux status bar. | Summary appears in status-right; updates on each status interval. |
| CT23 | **Activity log** — On Stop, append a timestamped line to `~/.local/state/claude-tmux/activity.log`: ISO 8601 timestamp, label, workspace, `completed/active`. A companion command shows recent entries. | Log entry written on stop; entry contains correct counts. |
| CT24 | **Persistent state** — State files written to `~/.local/state/claude-tmux/` instead of `$TMPDIR`, surviving reboots and tmux-resurrect restores. Session picker reflects prior sessions after reboot. | Reboot tmux; picker shows sessions from before reboot. |
| CT25 | **Multi-session key isolation** — State files keyed on `session_id:window_id` to prevent collision when two tmux sessions use overlapping window IDs (possible after server restart). | Two tmux sessions with same window IDs (simulated) → correct per-window state. |

---

## Non-functional requirements

| ID | Requirement |
|----|-------------|
| NFR1 | Each hook script completes within 100ms on typical hardware. The critical path is: jq parse + 5× `cat` state reads + `tmux rename-window`. |
| NFR2 | No hook script blocks on stdin after the initial `HOOK_DATA=$(cat)` read. |
| NFR3 | Hook failure must not surface to Claude Code. All scripts exit 0; all tmux calls use `\|\| true`. |
| NFR4 | State files are written atomically (`printf '%s' ... > file`, not append) to avoid torn reads under concurrent hooks. |
| NFR5 | No root privileges required for installation or operation. |
| NFR6 | Requires: tmux ≥ 3.2 (`display-popup`), bash ≥ 4.0 (associative arrays), fzf, jq. |
| NFR7 | Compatible with Claude Code hook types: `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `Notification`. |
| NFR8 | Powerline separators and per-state colors are cosmetic add-ons. The core state machine works with default tmux styling and any monospace font. |
| NFR9 | Scripts are location-independent: `source` calls resolve relative to the script's own directory (`${BASH_SOURCE[0]%/*}/claude-window-lib`), not a hardcoded `~/.local/bin/`. |

---

## File layout (target)

```
claude-tmux/
  bin/
    claude-window-lib          # shared library (sourced, not executed)
    claude-window-init         # PreToolUse: bootup + CWD tracking
    claude-window-ask          # PreToolUse: AskUserQuestion indicator
    claude-window-status       # PostToolUse: TaskCreate/TaskUpdate counters
    claude-window-restore      # PostToolUse: transient state cleanup
    claude-window-reset        # Stop: stopped state + cleanup
    claude-window-subagent     # SubagentStop: subagent return indicator
    claude-window-notify       # Notification: permission/idle indicators
    claude-window-summary      # fzf session picker (called by tmux binding)
  shell/
    claude-label.bash          # claude-label function (source in .bashrc/.zshrc)
  tmux/
    oh-my-tmux.conf            # window status color rules for oh-my-tmux
    plain-tmux.conf            # equivalent rules for vanilla tmux
    bindings.conf              # prefix+f and prefix+P bindings
  install.sh                   # symlinks bin/, patches settings.json, prints tmux snippet
  spec.md                      # this file
  README.md
```

---

## Open questions

| # | Question | Owner |
|---|----------|-------|
| OQ1 | Should `.cwd` files be kept in `$TMPDIR` (fast, non-persistent) or `~/.local/state/claude-tmux/` (persistent across reboots, enables CT24)? The current implementation uses `$TMPDIR`; CT24 is a nice-to-have that would require migrating the path. | Architecture |
| OQ2 | `prefix+f` conflicts with oh-my-tmux's default find-window binding. Is `prefix+f` the right key, or should we ship a different default and document how to rebind? | UX |
| OQ3 | The install script must patch `~/.claude/settings.json`. This file may contain user settings unrelated to claude-tmux. The `jq` merge approach is safe for adding keys but could conflict if the user already has a `hooks` block. Should install.sh refuse to patch if hooks already exist and prompt the user to merge manually? | Installation |
