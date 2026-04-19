# claude-tmux

**Status:** `implemented`

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

Per-window state is stored as flat files in `$TMPDIR`, keyed by sanitized tmux window ID. The window ID (e.g. `@3`) is sanitized by removing all non-alphanumeric-underscore characters, yielding e.g. `claude-window-3.<ext>`.

| File | Content | Lifetime |
|------|---------|----------|
| `.cwd` | Absolute path of Claude's working directory | Created on bootup; **kept after stop** for session picker |
| `.total` | Total tasks created (integer) | Cleared on stop or all-deleted |
| `.completed` | Tasks that reached `completed` status | Cleared on stop |
| `.deleted` | Tasks that reached `deleted` status | Cleared on stop |
| `.label` | Session label (from env var or first task subject) | Cleared on stop |
| `.stopped` | Sentinel (value `1`) written on stop | Consumed (deleted) on next bootup |

**Design decision:** `.cwd` is intentionally kept after stop so that stopped sessions (`■`) remain visible in the session picker. The `.stopped` sentinel ensures the next Claude boot still triggers the `○` bootup indicator even when the CWD has not changed.

### Title format

- With tasks: `<symbol> <completed>/<active><label>` where `active = total - deleted` and label is prefixed with a space only when non-empty (`${label:+ $label}`).
- Without tasks: `<symbol> <workspace>` where workspace is the basename of the stored `.cwd` path.

**Counter semantics:** `completed/active` is used (not `started/active`). This reads as "N tasks done out of M total active tasks" and remains accurate through the full lifecycle: `▶ 0/5` → `▶ 3/5` → `✓ 5/5`.

### Hook wiring (`~/.claude/settings.json`)

| Event | Matcher | Script | Order |
|-------|---------|--------|-------|
| PreToolUse | `.*` | `claude-window-init` | 1 |
| PreToolUse | `AskUserQuestion` | `claude-window-ask` | 2 |
| PostToolUse | `TaskCreate\|TaskUpdate` | `claude-window-status` | 1 |
| PostToolUse | `.*` | `claude-window-restore` | 2 |
| Stop | — | `claude-window-reset` | — |
| SubagentStop | — | `claude-window-subagent` | — |
| Notification | — | `claude-window-notify` | — |

Hook execution order within an event matters: for PostToolUse, `claude-window-status` runs before `claude-window-restore` so the restore hook sees updated counters. For PreToolUse, `claude-window-init` runs before `claude-window-ask` so the ask hook can overwrite the `○` that init may have just set.

### Hook JSON fields consumed

| Hook event | Fields read | Notes |
|------------|-------------|-------|
| PostToolUse (TaskCreate) | `tool_name`, `tool_input.subject` | `subject` (not `name`) is the task title field |
| PostToolUse (TaskUpdate) | `tool_name`, `tool_input.status` | Values: `pending`, `in_progress`, `completed`, `deleted` |
| Notification | `notification_type`, `cwd` | Types: `permission_prompt`, `idle_prompt` |
| All hooks | `$TMUX_PANE` env var | Used to resolve the correct tmux window ID |

**Window ID resolution:** Hooks run as subprocesses. `$TMUX_PANE` (set by tmux in the pane environment) identifies the pane where Claude is running. `tmux display-message -t "$TMUX_PANE" -p '#{window_id}'` resolves the window ID from the pane, ensuring the correct window is renamed even when the user has focused a different window. Falls back to active client window when `$TMUX_PANE` is unset.

### Session labeling

`CLAUDE_WINDOW_LABEL` is an exported environment variable that overrides the auto-derived label for a session. The `claude-label <name>` shell function sets it and immediately renames the current tmux window to `○ <name>`, providing pre-session context before any tool call fires.

When `CLAUDE_WINDOW_LABEL` is unset, the label is derived from the `subject` field of the first `TaskCreate` call: lowercased, spaces replaced with hyphens, truncated to 24 characters.

The label is fixed for the session duration; subsequent `TaskCreate` calls do not overwrite it.

### Session picker

`prefix+f` opens a tmux `display-popup` running an `fzf` picker over all tmux windows that have a `.cwd` state file. This includes both active (`▶`, `✓`, `?`, `!`) and recently stopped (`■`) sessions. The picker displays the current window title (already carrying the state symbol) alongside the abbreviated CWD (`$HOME` collapsed to `~`). Selecting an entry switches the tmux client to that window's session and focuses the window. Orphaned state files (window no longer exists in tmux) are cleaned up automatically on each picker open.

**Note:** `prefix+f` overrides oh-my-tmux's default find-window binding. See OQ2.

### Pane picker

`prefix+P` opens a `display-popup` running an `fzf` picker over all tmux panes across all sessions (`tmux list-panes -a`), showing `session:window.pane`, window name, current path, and running command. Enter switches to the selected pane.

### Required tmux settings

These settings must be active for the integration to work correctly:

| Setting | Value | Reason |
|---------|-------|--------|
| `automatic-rename` | `on` | Allows hook scripts to set window names freely; tmux auto-renames back when disabled |
| `bell-action` | `any` | Allows the BEL character written to the pane tty (permission alert) to produce an audible alert in the terminal emulator |
| `visual-bell` | `off` | Prevents screen flash on bell; audio-only alert is preferred |
| `visual-activity` | `off` | Suppresses activity indicators that would conflict with state symbols |
| `visual-silence` | `off` | Same |

**Window status format:** The oh-my-tmux `window_bell_flag` suffix (`#{?window_bell_flag,!,}`) must be removed from `tmux_conf_theme_window_status_format` and `tmux_conf_theme_window_status_current_format`. Without this, a permission prompt produces `! title !` — the symbol in the title and the bell flag indicator are redundant.

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
**Flow:** Hook fires, window title changes to `! N/M label`, audible bell is written to the pane's tty (`printf '\a' > $PANE_TTY`). Terminal emulator produces an audio alert.  
**Success:** Bell rings; window tab shows `!`; developer can respond without polling.

### UC3 — Navigate to a specific Claude session

**Actor:** Developer with multiple Claude sessions open  
**Trigger:** Developer wants to switch to a session by name or state  
**Goal:** Jump to any Claude window quickly  
**Flow:** `prefix+f` → fzf popup with all Claude windows (active + stopped) → select → tmux switches.  
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
**Flow:** Stop hook fires → window renamed `■ N/M label` → desktop notification sent (if tasks ran).  
**Success:** Tab shows `■`; notification shows label and task count; session remains visible in picker.

### UC6 — Install on a new machine

**Actor:** Developer setting up a new workstation  
**Trigger:** Developer wants the full claude-tmux system  
**Flow:** Clone repo → `./setup.sh install` → restart shell → add tmux config snippet → `prefix+r` in tmux.  
**Success:** All hooks active; window titles update; `prefix+f` opens picker.

---

## Requirements

### Must have

| ID | Requirement | Acceptance |
|----|-------------|------------|
| CT1 | **Shared library** — `claude-window-lib` provides: `cw_resolve_window` (sets `WINDOW_ID` and `BASE` from `$TMUX_PANE` or active client; returns 1 on failure), `cw_read_state` (reads `.total`, `.completed`, `.deleted`, `.label` into globals; computes `active = total - deleted`), `cw_title` (prints `▶ N/M` or `✓ N/N` with conditional label suffix), and `cw_workspace` (returns basename of `.cwd` content, falls back to `$PWD`). All hook scripts `source` this library. None duplicate window ID resolution or state reading. | All 7 hook scripts contain `source .../claude-window-lib`; no script contains its own pane-to-window-ID resolution. |
| CT2 | **Window title updated on every state transition** — Each hook script calls `tmux rename-window -t "$WINDOW_ID"` with the correct title for its event. Titles match the format defined in the State machine table. | Manual test: create task → `▶ 0/1 label`; complete task → `✓ 1/1 label`; stop → `■ 1/1 label`; reboot Claude → `○ workspace`. |
| CT3 | **Progress counter: `completed/active`** — `active = total − deleted`. `completed` increments on TaskUpdate `completed`. `deleted` increments on TaskUpdate `deleted`. No counter is modified on `in_progress` or `pending` status. `in_progress` TaskUpdate exits the hook without renaming (title is already `▶`, counts unchanged). | Task create (total=1) → `▶ 0/1`; complete → `✓ 1/1`; create second, delete it → `✓ 1/1` (active stays 1). |
| CT4 | **Label: no trailing space when empty** — All title-generating code uses `${label:+ $label}` so that sessions without a label do not produce a trailing space in the window name. | Session with no label or CLAUDE_WINDOW_LABEL: title is `▶ 0/1` not `▶ 0/1 `. |
| CT5 | **Workspace from `.cwd`, not `$PWD`** — All hooks that display a workspace name call `cw_workspace()` which reads `${BASE}.cwd`. Falls back to `$PWD` only when the file is absent. The hook subprocess's `$PWD` is Claude's launch directory and does not reflect CWD changes mid-session. | Change CWD mid-session; all-tasks-deleted branch shows updated workspace, not launch dir. |
| CT6 | **Bootup indicator** — `claude-window-init` shows `○ workspace` on: (a) first tool call (no `.cwd` file); (b) CWD change (`stored_cwd != $PWD`); (c) restart after stop (`.stopped` file present, consumed on first tool call). Does nothing when `total > 0`. | Three scenarios tested manually; `○` appears exactly when expected and not on unrelated tool calls during active work. |
| CT7 | **All-tasks-deleted clears state** — When `deleted == total` inside `claude-window-status`, all counter and label files are removed and the title becomes `○ workspace`. `.cwd` is NOT removed (session stays in picker). `.stopped` is NOT written (session is still live). | Delete all tasks mid-session → `○ workspace`; picker still lists window; Claude continues running. |
| CT8 | **Stop hook** — `claude-window-reset` on Stop: (a) shows `■ completed/active<label>` if `total > 0`; (b) removes all counter and label files; (c) keeps `.cwd`; (d) writes `.stopped` sentinel. When `total == 0`, leaves current title unchanged. | After stop: tab shows `■`; `.cwd` exists; `.total` absent; `.stopped` exists. After stop with no tasks: tab unchanged; `.stopped` still written (bootup indicator for next session). |
| CT9 | **Restore hook clears transient states** — `claude-window-restore` fires on every PostToolUse (`.*`) and overwrites any `?`, `!`, `·`, `↩` title with the correct progress state (`cw_title()` or `○ workspace`). Stop always fires after the last PostToolUse, so restore is never racing against `.stopped`. | After `?` appears (AskUserQuestion), next tool use restores `▶`/`✓`/`○`. After stop (where restore cannot fire), `■` is preserved. |
| CT10 | **Permission alert** — `claude-window-notify` on `permission_prompt`: (a) sets window title to `! completed/active<label>` or `! workspace`; (b) writes `\a` (BEL) to `#{pane_tty}` of the Claude pane. No desktop notification is sent on permission prompts (bell is sufficient; desktop popups are intrusive for a frequent event). | Bell rings in terminal emulator; tab shows `!`; no system notification popup appears. |
| CT11 | **Idle prompt** — `claude-window-notify` on `idle_prompt`: sets title to `· completed/active<label>` or `· workspace`. No bell. | Tab shows `·` when Claude enters idle prompt. |
| CT12 | **Session picker** — `claude-window-summary` lists all windows with a `.cwd` state file (active + stopped). Display: window title left-padded to 36 chars followed by abbreviated CWD (`$HOME → ~`). fzf header labels columns. Enter switches tmux client to selected window (`switch-client -t session:window_id`). Orphaned `.cwd` files (window ID not in `tmux list-windows -a`) are deleted along with all sibling state files on picker open. | Picker with 3 windows (active, stopped, different CWD) → all 3 listed; closed window → cleaned up and absent; select → window focused. |
| CT13 | **Session labeling** — `claude-label <name>` sets `CLAUDE_WINDOW_LABEL` and renames current tmux window to `○ <name>`. `claude-window-status` on first `TaskCreate` uses `CLAUDE_WINDOW_LABEL` if set, else derives label from `tool_input.subject` (lowercase, spaces→hyphens, max 24 chars). Label fixed for session duration. | `claude-label foo` → window shows `○ foo`; first task creates → `▶ 0/1 foo`; second task → `▶ 0/2 foo` (label unchanged). |
| CT14 | **Hook failure is silent** — All scripts exit 0. All `tmux rename-window` calls append `2>/dev/null \|\| true`. A missing or broken tmux session never causes a hook to return non-zero. | Kill tmux session while Claude runs → no error message from Claude Code hooks. |
| CT15 | **Stop notification (macOS only)** — On Stop with `total > 0`, sends an `osascript` desktop notification when `osascript` is present. No Linux notification path; Linux users rely on the `■` tab title + activity log. No notification when no tasks ran. | Stop after tasks on macOS → notification shown. Linux → no notification attempted. No tasks → no notification either OS. |
| CT16 | **setup.sh** — Single entrypoint (`install \| uninstall \| doctor \| selftest`). `install` symlinks all scripts from `bin/` to `~/.local/bin/`, merges the hook block into `~/.claude/settings.json` using `jq` (see OQ3), and prints the tmux config snippet. Scripts use relative `source` paths (`${BASH_SOURCE[0]%/*}/claude-window-lib`) so they work from any install location. Idempotent. | Fresh system: run `setup.sh install` → hooks active after shell restart. Run again → no duplicate symlinks, no duplicate JSON keys. Symlinks point to repo; editing repo files takes effect immediately. `setup.sh uninstall` reverses everything. |
| CT17 | **tmux bell settings** — `bell-action any`, `visual-bell off`, `visual-activity off`, `visual-silence off` must be set in tmux config. `window_bell_flag` suffix (`#{?window_bell_flag,!,}`) must be removed from oh-my-tmux window status format variables to prevent `! title !` redundancy. | Permission prompt → single `!` prefix in tab, no trailing `!`. Audible bell rings. |
| CT18 | **`automatic-rename on`** — tmux must have `automatic-rename on`. Without it, rename-window calls are silently ignored by tmux (the default is off in some distros). | Scripts set title → title visible in tab (not blank or old name). |

### Should have

| ID | Requirement | Acceptance |
|----|-------------|------------|
| CT19 | **oh-my-tmux window status colors** — Per-state color rules for `tmux_conf_theme_window_status_format` and `tmux_conf_theme_window_status_current_format` ship as a config snippet. Colors: `▶` blue (colour75/colour75), `✓` green (colour76/colour156), `!` red (colour196/colour210), `?` gold (colour220/colour227), `■` dark gray (colour239/colour102), `↩` lavender (colour141/colour183), `·` dim gray (colour244/colour250). Uses `#{m/r:^SYMBOL,#W}` regex match. | Snippet documented; colors render correctly with oh-my-tmux and a Powerline/Nerd font. |
| CT20 | **Plain tmux config variant** — A companion config file provides equivalent `set -g window-status-format` / `set -g window-status-current-format` rules for users without oh-my-tmux. | Snippet documented and tested with vanilla tmux 3.2. |
| CT21 | **Pane picker** — `prefix+P` opens a `display-popup -E` fzf picker over all tmux panes (`tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}  [#{window_name}] #{b:pane_current_path} (#{pane_current_command})'`). Enter switches to selected pane via `tmux switch-client -t`. | Open picker → all panes listed; select → pane focused. |
| CT22 | **Subagent return indicator** — `claude-window-subagent` (SubagentStop hook) sets `↩ completed/active<label>` or `↩ workspace` briefly; cleared by next PostToolUse restore. | SubagentStop fires → `↩` appears; next tool use → previous state restored. |
| CT23 | **`claude-label` ships as a standalone sourced file** — `shell/claude-label.bash` can be sourced directly from `.bashrc`/`.zshrc` without oh-my-bash. oh-my-bash users can load it as a custom plugin at `~/.oh-my-bash/custom/plugins/claude-label/claude-label.plugin.bash`. | `source shell/claude-label.bash` → `claude-label` function available in any bash/zsh session. |
| CT24 | **Powerline separators** — oh-my-tmux separator variables ship pre-configured with Nerd Font Unicode escapes (`\uE0B0`–`\uE0B3`). ASCII fallback config also provided. | With Nerd Font: Powerline separators render. With ASCII fallback: `|` separators, no broken glyphs. |
| CT25 | **Status-line simplification** — The reference `tmux.conf.local` snippet removes username and uptime from `tmux_conf_theme_status_right` and reduces `tmux_conf_theme_status_left` to session name only (`❐ #S`). | Status bar shows: session name left; time, date, hostname right. No uptime, no username. |

### Nice to have

| ID | Requirement | Acceptance |
|----|-------------|------------|
| CT26 | **Status-right aggregate** — A script callable from `status-right` scans all `$TMPDIR/claude-window-*.cwd` files and emits a compact count of active Claude windows (e.g. `2▶ 1✓`). | Summary appears in status-right; updates on each status interval. |
| CT27 | **Activity log** — On Stop, appends a timestamped line to `~/.local/state/claude-tmux/activity.log`: ISO 8601 timestamp, label, workspace, `completed/active`. A companion command (`claude-tmux-log`) prints recent entries. | Log entry written on stop; entry contains correct fields. |
| CT28 | **Persistent state** — State files written to `~/.local/state/claude-tmux/` instead of `$TMPDIR`, surviving reboots and tmux-resurrect restores. Session picker reflects prior sessions after reboot. | Reboot tmux; picker shows sessions from before reboot. |
| CT29 | **Multi-session key isolation** — State files keyed on `session_id:window_id` (or similar collision-resistant key) to prevent state bleed when two tmux sessions use overlapping window IDs after a server restart. | Two tmux sessions with identical window IDs → correct per-window state in picker. |

---

## Non-functional requirements

| ID | Requirement |
|----|-------------|
| NFR1 | Each hook script completes within 100ms on typical hardware. The critical path is: source lib + jq parse + 4–5× `cat` state reads + `tmux rename-window`. |
| NFR2 | No hook script blocks on stdin after the initial `HOOK_DATA=$(cat)` read. |
| NFR3 | Hook failure must not surface to Claude Code. All scripts exit 0; all tmux calls use `\|\| true`. |
| NFR4 | State files are written atomically (`printf '%s' ... > file`, not append) to avoid partial reads when two hooks fire in close succession. |
| NFR5 | No root privileges required for installation or operation. |
| NFR6 | Minimum requirements: tmux ≥ 3.2 (`display-popup`), bash ≥ 4.0 (associative arrays in `claude-window-summary`), fzf, jq. |
| NFR7 | Compatible with Claude Code hook event types: `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `Notification`. Hook JSON shapes must not be assumed stable; field reads use `// ""` fallback via jq. |
| NFR8 | Powerline separators and per-state colors are cosmetic. The core state machine works with default tmux styling and any monospace font. |
| NFR9 | Scripts are location-independent: lib `source` calls resolve relative to the script's own directory via `${BASH_SOURCE[0]%/*}/claude-window-lib`, not a hardcoded `~/.local/bin/`. |
| NFR10 | The `claude-label` function must use `export` so `CLAUDE_WINDOW_LABEL` is visible to Claude Code's hook subprocess environment. |

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
    claude-window-reset        # Stop: stopped state + cleanup + activity log
    claude-window-subagent     # SubagentStop: subagent return indicator
    claude-window-notify       # Notification: permission/idle indicators + bell
    claude-window-summary      # fzf session picker (invoked by tmux binding)
    claude-window-pane         # fzf pane picker across all sessions (CT21)
    claude-window-aggregate    # tmux status-right: compact count of active Claude windows
    claude-tmux-log            # activity log viewer (claude-tmux-log [-n N])
  tests/
    smoke.sh                   # stub-tmux harness asserting each hook's rename-window call
  shell/
    claude-label.bash          # claude-label function; doubles as oh-my-bash plugin
  tmux/
    oh-my-tmux.conf            # window status color rules + separator config
    plain-tmux.conf            # equivalent rules for vanilla tmux
    bindings.conf              # prefix+f (session picker) and prefix+P (pane picker)
    settings.conf              # required tmux option overrides (bell-action, automatic-rename, etc.)
  specs/
    index.md                   # table of record
    done/
      claude-tmux/
        spec.md                # this file
  setup.sh                     # single entrypoint: install | uninstall | doctor | selftest
  README.md
```

---

## Design decisions (recorded)

| Decision | Rationale |
|----------|-----------|
| `completed/active` not `started/active` | `started` counted tasks that ever went `in_progress`, causing `▶ 5/5` when all 5 tasks were started but none complete. `completed/active` reads unambiguously as a progress bar. |
| No desktop notification on permission prompt | Bell is sufficient for an event that may fire frequently. Desktop notifications on permission prompts would be intrusive and would appear even when the developer is actively watching the terminal. Desktop notification retained for Stop (a less frequent, higher-signal event). |
| `.cwd` survives Stop | Stopped sessions (`■`) should remain visible in the session picker so the developer can navigate back to a finished window. The `.stopped` sentinel provides a separate signal for the bootup indicator without relying on `.cwd` absence. |
| `bell-action any`, not `bell-action other` | Permission prompts may fire in the currently focused Claude window (developer is in the same pane context). `other` would suppress the bell in that case. `any` ensures the bell always fires. |
| `window_bell_flag` suffix removed | oh-my-tmux appends `!` when a window has an uncleared bell flag. Combined with our `!` prefix symbol, this produces `! title !`. Removing the suffix eliminates redundancy; the state symbol is the authoritative indicator. |
| Label fixed to first TaskCreate | The session label represents the session, not individual tasks. Using the first task's subject as the label provides immediate context; overwriting on each task would cause the tab to show the most recent task name rather than the overall session context. |
| Workspace read from `.cwd`, not `$PWD` | Hook subprocess `$PWD` is Claude's launch directory and does not update when Claude changes its working directory mid-session. `.cwd` is written by `claude-window-init` on each CWD change and is the authoritative workspace source. |
| `prefix+f` for session picker | Overrides oh-my-tmux's default find-window on `f`. The native find-window is available as `prefix+:find-window` if needed. |
| State files in `~/.local/state/claude-tmux/` | `$TMPDIR` is cleared on reboot, losing session picker history and activity log (OQ1). `~/.local/state/` follows the XDG state home convention and survives reboots. The picker's orphan-cleanup pass handles stale entries when windows are closed. Overridable via `CLAUDE_TMUX_STATE_DIR`. |
| Session-qualified BASE key (`s${session_id}_w${window_id}`) | Window IDs in tmux are scoped to a server lifetime; after a server restart, `@0` is reused. Without session qualification, the new `@0` would inherit state files from the previous session's `@0`. The session_id monotonically increases within a server (`$0`, `$1`, …), making `s0_w3` stable for the life of a session. Both `cw_resolve_window` (lib) and the session picker (`claude-window-summary`) compute the key identically so file-to-window matching is guaranteed. |
| `claude-label.bash` doubles as oh-my-bash plugin | oh-my-bash plugins are sourced files with a `#! bash oh-my-bash.module` marker. Adding the marker to `claude-label.bash` means one file serves both `source /path/to/claude-label.bash` (plain shells) and the oh-my-bash plugin slot (via symlink), eliminating a wrapper file. The marker is a comment and does not affect non-oh-my-bash sourcing. |
| No Linux desktop-notification path | Out of scope. D-Bus discovery is fragile across non-systemd distros, Wayland, and remote/SSH tmux; the `■` tab title plus `activity.log` entry are sufficient primary signals. macOS uses `osascript` because the delivery path is deterministic. Linux users who want a stop bell can wire one via their terminal emulator's `bell-action` on the `■` rename. |

---

## Requirement traceability

| ID | Primary script(s) | Evidence |
|----|-------------------|----------|
| CT1 | `bin/claude-window-lib` | All hook scripts `source` the lib; `shellcheck` in CI enforces it. |
| CT2 | all hook scripts | `tests/smoke.sh` asserts each hook emits the expected `rename-window`. |
| CT3 | `claude-window-status` | `tests/smoke.sh` — TaskCreate/TaskUpdate sections. |
| CT4 | `claude-window-lib::cw_title` | `tests/smoke.sh` — assertions match titles with no trailing space. |
| CT5 | `claude-window-lib::cw_workspace` | Manual; hooks read `${BASE}.cwd`, never `$PWD` directly. |
| CT6 | `claude-window-init` | `tests/smoke.sh` — init section asserts `○` on clean state. |
| CT7 | `claude-window-status` (deleted branch) | Manual (delete-all path not in smoke; rm-files + rename verified in code review). |
| CT8 | `claude-window-reset` | `tests/smoke.sh` — reset section + `.stopped` sentinel check. |
| CT9 | `claude-window-restore` | `tests/smoke.sh` — restore section. |
| CT10 | `claude-window-notify` | `tests/smoke.sh` — permission_prompt section. |
| CT11 | `claude-window-notify` | `tests/smoke.sh` — idle_prompt section. |
| CT12 | `claude-window-summary` | `tests/smoke.sh` — picker + orphan + stale-sentinel GC sections. |
| CT13 | `shell/claude-label.bash`, `claude-window-status` | Manual; unit-testable via env var injection if needed. |
| CT14 | all hook scripts | `set -euo pipefail` + `trap 'exit 0' ERR` + `2>/dev/null \|\| true` on tmux calls. |
| CT15 | `claude-window-reset` | `tests/smoke.sh` — osascript stub asserts env-var delivery. Linux desktop notification is out of scope (see OQ4). |
| CT16 | `setup.sh` | `tests/install-uninstall.sh` asserts symlinks + hooks wiring. |
| CT17 | `tmux/settings.conf`, `tmux/oh-my-tmux.conf` | `claude-tmux-doctor` warns on mismatched runtime bell-action. |
| CT18 | `tmux/settings.conf` | `claude-tmux-doctor` fails on `automatic-rename off`. |
| CT19 | `tmux/oh-my-tmux.conf` | Manual (color rendering). |
| CT20 | `tmux/plain-tmux.conf` | Manual. |
| CT21 | `claude-window-pane` | `tests/smoke.sh` — pane picker section. |
| CT22 | `claude-window-subagent` | `tests/smoke.sh` — subagent section. |
| CT23 | `shell/claude-label.bash`, `setup.sh` | `tests/install-uninstall.sh` covers symlink wiring. |
| CT24 | `tmux/oh-my-tmux.conf` | Manual (glyph rendering). |
| CT25 | `tmux/oh-my-tmux.conf` | Manual. |
| CT26 | `claude-window-aggregate` | `tests/smoke.sh` — aggregate section (1▶ 1✓ 1■). |
| CT27 | `claude-window-reset`, `claude-tmux-log` | `tests/smoke.sh` — log rotation section; manual for viewer output. |
| CT28 | `claude-window-lib::cw_state_dir` | `CLAUDE_TMUX_STATE_DIR` env var covered in every test via override. |
| CT29 | `claude-window-lib::cw_resolve_window`, `claude-window-summary` | `tests/smoke.sh` — key-isolation section (same wid, different sid). |

## Open questions

| # | Question | Status |
|---|----------|--------|
| OQ1 | Should `.cwd` files be kept in `$TMPDIR` (fast, non-persistent) or `~/.local/state/claude-tmux/` (persistent across reboots, enables CT28)? | Resolved: `~/.local/state/claude-tmux/` chosen. All state files live there; orphan cleanup in picker handles stale entries. Override via `CLAUDE_TMUX_STATE_DIR`. |
| OQ2 | `prefix+f` conflicts with oh-my-tmux's default find-window binding. Should the default shipped binding be different, with documentation on how to use `f`? | Resolved: `prefix+f` chosen as the default; documented in Design decisions. |
| OQ3 | The install script must patch `~/.claude/settings.json`. If the user already has a `hooks` block, `jq` merge may drop existing entries or conflict. | Resolved: `setup.sh install` detects existing claude-window hooks (skips if already installed), merges per-event if a foreign hooks block exists, otherwise writes fresh. |
| OQ4 | Should stop notifications try to cover Linux via `notify-send` (requires `DBUS_SESSION_BUS_ADDRESS`, fragile on non-systemd / Wayland / SSH)? | Resolved: no. Linux desktop notifications are out of scope — the `■` tab symbol and `activity.log` entry are the primary Stop signal on every platform. macOS uses `osascript` because the delivery path is deterministic. |
