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
# Logs every invocation; answers display-message queries so cw_resolve_window
# succeeds. All other subcommands no-op and return 0.
cat > "$STUB_DIR/tmux" <<'STUB'
#!/bin/bash
printf 'tmux %s\n' "$*" >> "$TMUX_LOG"
case "$*" in
  *"#{window_id}"*)  printf '@0\n' ;;
  *"#{session_id}"*) printf '$0\n' ;;
  *"#{pane_tty}"*)   printf '/dev/null\n' ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/tmux"

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

printf '\n'
if [ "$fail" -eq 0 ]; then
  printf 'smoke: all assertions passed.\n'
else
  printf 'smoke: %d assertion(s) failed.\n' "$fail" >&2
fi
exit "$fail"
