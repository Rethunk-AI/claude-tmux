#!/usr/bin/env bash
# tests/install-uninstall.sh — run `setup.sh install` + `setup.sh uninstall`
# against a throw-away $HOME and assert that uninstall reverses install for
# symlinks and the settings.json hooks block.
#
# Requires: jq, bash >= 4.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_HOME="$(mktemp -d -t claude-tmux-io.XXXXXX)"
cleanup() { rm -rf "$FAKE_HOME"; }
trap cleanup EXIT

export HOME="$FAKE_HOME"
export CLAUDE_TMUX_STATE_DIR="$FAKE_HOME/.local/state/claude-tmux"

fail=0
pass() { printf '  PASS  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*" >&2; fail=1; }

printf '\n== install ==\n'
# install.sh echoes output; silence stdout but keep stderr for real errors.
if ! bash "$REPO/setup.sh" install >/dev/null; then
  bad "setup.sh install exited non-zero"
  exit 1
fi

for name in claude-window-init claude-window-status claude-window-reset \
            claude-window-summary claude-window-aggregate claude-tmux-log \
            claude-tmux-doctor; do
  if [ -L "$HOME/.local/bin/$name" ]; then
    pass "symlink: $name"
  else
    bad "symlink missing: $name"
  fi
done

SETTINGS="$HOME/.claude/settings.json"
if jq -e '
  .hooks // {}
  | [to_entries[] | .value[]? | .hooks[]? | .command // ""]
  | any(contains("claude-window-init"))
' "$SETTINGS" >/dev/null 2>&1; then
  pass "settings.json has claude-window-init hook"
else
  bad "settings.json missing claude-window-init hook"
fi

printf '\n== uninstall ==\n'
if ! bash "$REPO/setup.sh" uninstall >/dev/null; then
  bad "setup.sh uninstall exited non-zero"
fi

still=0
for name in claude-window-init claude-window-status claude-window-reset \
            claude-window-summary claude-window-aggregate claude-tmux-log \
            claude-tmux-doctor; do
  [ -e "$HOME/.local/bin/$name" ] && still=$((still + 1))
done
if [ "$still" -eq 0 ]; then
  pass "all symlinks removed"
else
  bad "$still symlink(s) remain after uninstall"
fi

if jq -e '
  .hooks // {}
  | [to_entries[] | .value[]? | .hooks[]? | .command // ""]
  | any(contains("claude-window-"))
' "$SETTINGS" >/dev/null 2>&1; then
  bad "settings.json still references claude-window-* hooks"
else
  pass "settings.json hooks stripped"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  printf 'install-uninstall: all assertions passed.\n'
else
  printf 'install-uninstall: %d failure(s).\n' "$fail" >&2
fi
exit "$fail"
