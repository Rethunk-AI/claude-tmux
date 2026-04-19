#!/bin/bash
# tests/smoke.sh — fire each hook against a stub tmux and assert the expected
# rename-window argument was emitted. Covers the hook scripts only; the fzf
# pickers (summary, pane) and status-right aggregate are manual-only.
#
# Requires: bash >= 4, jq.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$(mktemp -d -t claude-tmux-smoke-state.XXXXXX)"
STUB_DIR="$(mktemp -d -t claude-tmux-smoke-stub.XXXXXX)"
TMUX_LOG="$STUB_DIR/tmux.log"

cleanup() { rm -rf "$STATE" "$STUB_DIR"; }
trap cleanup EXIT

# --- tmux stub -----------------------------------------------------------
# Logs every invocation. Answers display-message queries so cw_resolve_window
# succeeds. For list-windows / list-panes, emits whatever canned output is in
# $TMUX_LIST_WINDOWS_OUT / $TMUX_LIST_PANES_OUT so the pickers and aggregate
# can be exercised. All other subcommands no-op and return 0.
cat > "$STUB_DIR/tmux" <<'STUB'
#!/bin/bash
printf 'tmux %s\n' "$*" >> "$TMUX_LOG"
case "$1" in
  list-windows)
    [ -n "${TMUX_LIST_WINDOWS_OUT:-}" ] && printf '%s\n' "$TMUX_LIST_WINDOWS_OUT"
    exit 0
    ;;
  list-panes)
    [ -n "${TMUX_LIST_PANES_OUT:-}" ] && printf '%s\n' "$TMUX_LIST_PANES_OUT"
    exit 0
    ;;
  show-options)
    case "$*" in
      *automatic-rename*) printf 'automatic-rename on\n' ;;
      *bell-action*)      printf 'bell-action any\n' ;;
    esac
    exit 0
    ;;
esac
case "$*" in
  *"#{window_id}"*)  printf '@0\n' ;;
  *"#{session_id}"*) printf '$0\n' ;;
  *"#{pane_tty}"*)   printf '/dev/null\n' ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/tmux"

# --- fzf stub: print the first input line ---
cat > "$STUB_DIR/fzf" <<'STUB'
#!/bin/bash
head -n 1
STUB
chmod +x "$STUB_DIR/fzf"

export PATH="$STUB_DIR:$PATH"
export TMUX=1 TMUX_PANE=%0
export CLAUDE_TMUX_STATE_DIR="$STATE"
export TMUX_LOG

# Key after digit-stripping of @0 / $0 (both collapse to "0"):
KEY_BASE="$STATE/claude-window-s0_w0"

fail=0
assert() {
  local name="$1" pattern="$2"
  if grep -Eq "$pattern" "$TMUX_LOG"; then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s  (no match for /%s/)\n' "$name" "$pattern" >&2
    sed 's/^/        /' "$TMUX_LOG" >&2
    fail=1
  fi
}

run() {
  local script="$1"
  : > "$TMUX_LOG"
  if [ "$#" -gt 1 ]; then
    printf '%s' "$2" | "$REPO/bin/$script"
  else
    "$REPO/bin/$script"
  fi
}

printf '\n== init ==\n'
rm -f "$STATE"/claude-window-*
run claude-window-init
assert 'init: ○ bootup title on clean state' 'rename-window.*○ '

printf '\n== status TaskCreate ==\n'
printf '%s' "$PWD" > "$KEY_BASE.cwd"
run claude-window-status '{"tool_name":"TaskCreate","tool_input":{"subject":"hello world"}}'
assert 'status: TaskCreate yields ▶ 0/1' 'rename-window.*▶ 0/1'
if [ "$(cat "$KEY_BASE.total" 2>/dev/null)" != "1" ]; then
  printf '  FAIL  .total should be 1 after TaskCreate\n' >&2; fail=1
fi

printf '\n== status TaskUpdate completed ==\n'
run claude-window-status '{"tool_name":"TaskUpdate","tool_input":{"status":"completed"}}'
assert 'status: TaskUpdate completed yields ✓ 1/1' 'rename-window.*✓ 1/1'

printf '\n== reset ==\n'
run claude-window-reset
assert 'reset: ■ 1/1 title on stop' 'rename-window.*■ 1/1'
[ -f "$KEY_BASE.stopped" ] || { printf '  FAIL  .stopped sentinel not written\n' >&2; fail=1; }
[ ! -f "$KEY_BASE.total" ] || { printf '  FAIL  .total not cleared after stop\n' >&2; fail=1; }

printf '\n== ask ==\n'
printf '1' > "$KEY_BASE.total"
printf '0' > "$KEY_BASE.completed"
printf '0' > "$KEY_BASE.deleted"
printf 'smoke' > "$KEY_BASE.label"
run claude-window-ask
assert 'ask: ? prefix with progress counters' 'rename-window.*\? 0/1'

printf '\n== notify permission_prompt ==\n'
run claude-window-notify "{\"notification_type\":\"permission_prompt\",\"cwd\":\"$PWD\"}"
assert 'notify: ! prefix on permission_prompt' 'rename-window.*! 0/1'

printf '\n== notify idle_prompt ==\n'
run claude-window-notify "{\"notification_type\":\"idle_prompt\",\"cwd\":\"$PWD\"}"
assert 'notify: · prefix on idle_prompt' 'rename-window.*· 0/1'

printf '\n== subagent ==\n'
run claude-window-subagent
assert 'subagent: ↩ prefix with counters' 'rename-window.*↩ 0/1'

printf '\n== restore ==\n'
run claude-window-restore
assert 'restore: progress title after transient states' 'rename-window.*(▶|✓|○) '

# --- picker: summary ----------------------------------------------------
printf '\n== picker: summary ==\n'
rm -f "$STATE"/claude-window-*
# Seed 3 keys: live active (s0_w0), live stopped (s0_w1), orphan (s9_w9).
printf '%s' "$PWD" > "$STATE/claude-window-s0_w0.cwd"
printf '1'       > "$STATE/claude-window-s0_w0.total"
printf '%s' "$PWD" > "$STATE/claude-window-s0_w1.cwd"
printf '1'       > "$STATE/claude-window-s0_w1.stopped"
printf '%s' "$PWD" > "$STATE/claude-window-s9_w9.cwd"

export TMUX_LIST_WINDOWS_OUT=$'@0\t$0\tmain\tone\n@1\t$0\tmain\ttwo'
: > "$TMUX_LOG"
"$REPO/bin/claude-window-summary" >/dev/null 2>&1 || true
assert 'summary: switch-client invoked with selected target' 'switch-client -t main:@'
if [ ! -f "$STATE/claude-window-s9_w9.cwd" ]; then
  printf '  PASS  summary: orphan s9_w9 cleaned up\n'
else
  printf '  FAIL  summary: orphan s9_w9 state not cleaned\n' >&2; fail=1
fi
unset TMUX_LIST_WINDOWS_OUT

# --- session-qualified key isolation ------------------------------------
printf '\n== key isolation (same wid, different sid) ==\n'
rm -f "$STATE"/claude-window-*
printf '%s' "$PWD" > "$STATE/claude-window-s0_w0.cwd"
printf 'A'        > "$STATE/claude-window-s0_w0.label"
printf '%s' "$PWD" > "$STATE/claude-window-s1_w0.cwd"
printf 'B'        > "$STATE/claude-window-s1_w0.label"
export TMUX_LIST_WINDOWS_OUT=$'@0\t$0\tmain\tone\n@0\t$1\tother\ttwo'
: > "$TMUX_LOG"
"$REPO/bin/claude-window-summary" >/dev/null 2>&1 || true
if [ -f "$STATE/claude-window-s0_w0.label" ] && [ -f "$STATE/claude-window-s1_w0.label" ]; then
  printf '  PASS  both sid-qualified keys retained\n'
else
  printf '  FAIL  sid-qualified keys collided or were dropped\n' >&2; fail=1
fi
unset TMUX_LIST_WINDOWS_OUT

# --- picker: pane -------------------------------------------------------
printf '\n== picker: pane ==\n'
export TMUX_LIST_PANES_OUT=$'main:1.0\t[one] /tmp (bash)\nmain:2.0\t[two] /tmp (bash)'
: > "$TMUX_LOG"
"$REPO/bin/claude-window-pane" >/dev/null 2>&1 || true
assert 'pane: switch-client invoked' 'switch-client -t main:1.0'
unset TMUX_LIST_PANES_OUT

# --- aggregate ----------------------------------------------------------
printf '\n== aggregate ==\n'
rm -f "$STATE"/claude-window-*
# s0_w0 in progress; s0_w1 complete; s0_w2 stopped; s9_w9 orphan
printf '%s' "$PWD" > "$STATE/claude-window-s0_w0.cwd"
printf '3'        > "$STATE/claude-window-s0_w0.total"
printf '1'        > "$STATE/claude-window-s0_w0.completed"
printf '%s' "$PWD" > "$STATE/claude-window-s0_w1.cwd"
printf '2'        > "$STATE/claude-window-s0_w1.total"
printf '2'        > "$STATE/claude-window-s0_w1.completed"
printf '%s' "$PWD" > "$STATE/claude-window-s0_w2.cwd"
printf '1'        > "$STATE/claude-window-s0_w2.stopped"
printf '%s' "$PWD" > "$STATE/claude-window-s9_w9.cwd"
printf '5'        > "$STATE/claude-window-s9_w9.total"

export TMUX_LIST_WINDOWS_OUT=$'$0 @0\n$0 @1\n$0 @2'
out=$("$REPO/bin/claude-window-aggregate" 2>/dev/null || true)
if [ "$out" = "1▶ 1✓ 1■ " ]; then
  printf '  PASS  aggregate output: %q\n' "$out"
else
  printf '  FAIL  aggregate output was %q (expected "1▶ 1✓ 1■ ")\n' "$out" >&2; fail=1
fi
unset TMUX_LIST_WINDOWS_OUT

# --- macOS AppleScript notification path -------------------------------
printf '\n== reset: osascript path ==\n'
rm -f "$STATE"/claude-window-*
printf '%s' "$PWD" > "$STATE/claude-window-s0_w0.cwd"
printf '1'        > "$STATE/claude-window-s0_w0.total"
printf '1'        > "$STATE/claude-window-s0_w0.completed"
OSASCRIPT_LOG="$STUB_DIR/osascript.log"
cat > "$STUB_DIR/osascript" <<OSA
#!/bin/bash
printf 'body=%s title=%s\n' "\${CLAUDE_TMUX_BODY:-}" "\${CLAUDE_TMUX_TITLE:-}" > "$OSASCRIPT_LOG"
exit 0
OSA
chmod +x "$STUB_DIR/osascript"
"$REPO/bin/claude-window-reset" >/dev/null 2>&1 || true
if [ -f "$OSASCRIPT_LOG" ] && grep -q 'title=Claude finished' "$OSASCRIPT_LOG"; then
  printf '  PASS  osascript invoked with env-vars (no shell injection)\n'
else
  printf '  FAIL  osascript not invoked correctly\n' >&2
  [ -f "$OSASCRIPT_LOG" ] && sed 's/^/        /' "$OSASCRIPT_LOG" >&2
  fail=1
fi
rm -f "$STUB_DIR/osascript" "$OSASCRIPT_LOG"
[ -f "$STATE/claude-window-s0_w0.stopped" ] || { printf '  FAIL  reset: .stopped not written\n' >&2; fail=1; }

# --- log rotation -------------------------------------------------------
printf '\n== reset: log rotation ==\n'
rm -f "$STATE"/claude-window-* "$STATE/activity.log" "$STATE/activity.log.1"
printf '%s' "$PWD" > "$STATE/claude-window-s0_w0.cwd"
printf '1'        > "$STATE/claude-window-s0_w0.total"
printf '1'        > "$STATE/claude-window-s0_w0.completed"
# Pre-seed activity.log past the 1KB cap to force rotation on next Stop.
head -c 2048 /dev/zero | tr '\0' 'x' > "$STATE/activity.log"
CLAUDE_TMUX_LOG_MAX_BYTES=1024 "$REPO/bin/claude-window-reset" >/dev/null 2>&1 || true
if [ -f "$STATE/activity.log.1" ]; then
  printf '  PASS  activity.log rotated to .1 at size cap\n'
else
  printf '  FAIL  activity.log not rotated\n' >&2; fail=1
fi

# --- stale .stopped GC --------------------------------------------------
printf '\n== summary: stale .stopped GC ==\n'
rm -f "$STATE"/claude-window-*
printf '%s' "$PWD" > "$STATE/claude-window-s0_w0.cwd"
printf '1'        > "$STATE/claude-window-s0_w0.stopped"
# Backdate sentinel 40 days
touch -t "$(date -u -d '40 days ago' +%Y%m%d%H%M 2>/dev/null \
          || date -u -v-40d +%Y%m%d%H%M)" "$STATE/claude-window-s0_w0.stopped"
export TMUX_LIST_WINDOWS_OUT=$'@0\t$0\tmain\tone'
CLAUDE_TMUX_STOPPED_MAX_DAYS=30 "$REPO/bin/claude-window-summary" >/dev/null 2>&1 || true
if [ ! -f "$STATE/claude-window-s0_w0.cwd" ]; then
  printf '  PASS  stale stopped sentinel and siblings swept\n'
else
  printf '  FAIL  stale stopped sentinel not swept\n' >&2; fail=1
fi
unset TMUX_LIST_WINDOWS_OUT

printf '\n'
if [ "$fail" -eq 0 ]; then
  printf 'smoke: all assertions passed.\n'
else
  printf 'smoke: %d assertion(s) failed.\n' "$fail" >&2
fi
exit "$fail"
