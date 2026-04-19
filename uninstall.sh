#!/usr/bin/env bash
# uninstall.sh — reverse install.sh on a machine
#
# What this does (in order):
#   1. Remove bin/ symlinks from ~/.local/bin/
#   2. Remove the oh-my-bash claude-label plugin (if present)
#   3. Strip claude-window-* hooks from ~/.claude/settings.json
#   4. Print remaining manual cleanup (tmux conf, state dir, shell rc)
#
# State directory and tmux conf source-file lines are left in place so the
# user can decide whether to keep session history and re-install.
#
# Requirements: jq (same as install.sh).

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
STATE_DIR="${CLAUDE_TMUX_STATE_DIR:-${HOME}/.local/state/claude-tmux}"
SETTINGS="${HOME}/.claude/settings.json"
OMB_PLUGIN_DIR="${HOME}/.oh-my-bash/custom/plugins/claude-label"

EXECUTABLES=(
  claude-window-init
  claude-window-ask
  claude-window-status
  claude-window-restore
  claude-window-reset
  claude-window-subagent
  claude-window-notify
  claude-window-summary
  claude-window-aggregate
  claude-window-pane
  claude-tmux-log
  claude-tmux-doctor
)

# --- 1. Remove bin symlinks ---

printf 'Removing bin symlinks...\n'
removed=0
for name in "${EXECUTABLES[@]}"; do
  target="$BIN_DIR/$name"
  if [ -L "$target" ]; then
    rm "$target"
    printf '  removed: %s\n' "$target"
    removed=$((removed + 1))
  fi
done
[ "$removed" -eq 0 ] && printf '  (none found)\n'
printf '\n'

# --- 2. Remove oh-my-bash plugin ---

target="$OMB_PLUGIN_DIR/claude-label.plugin.bash"
if [ -L "$target" ] || [ -f "$target" ]; then
  rm "$target"
  rmdir "$OMB_PLUGIN_DIR" 2>/dev/null || true
  printf 'Removed oh-my-bash plugin: %s\n\n' "$target"
fi

# --- 3. Strip claude-window-* hooks from settings.json ---

if [ -f "$SETTINGS" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    printf 'Warning: jq not found — skipping %s hook cleanup.\n' "$SETTINGS" >&2
    printf '         Remove any line containing `claude-window-` by hand.\n\n' >&2
  else
    tmp=$(mktemp)
    jq '
      if (.hooks | type) == "object" then
        .hooks = (
          .hooks
          | with_entries(
              .value = (
                .value
                | map(
                    .hooks = (.hooks // [] | map(select((.command // "") | contains("claude-window-") | not)))
                  )
                | map(select((.hooks // []) | length > 0))
              )
            )
          | with_entries(select((.value // []) | length > 0))
        )
        | (if (.hooks | length) == 0 then del(.hooks) else . end)
      else . end
    ' "$SETTINGS" > "$tmp"
    if ! cmp -s "$SETTINGS" "$tmp"; then
      mv "$tmp" "$SETTINGS"
      printf 'Stripped claude-window-* hooks from %s\n\n' "$SETTINGS"
    else
      rm "$tmp"
      printf 'No claude-window-* hooks found in %s\n\n' "$SETTINGS"
    fi
  fi
fi

# --- 4. Manual steps ---

cat <<INSTRUCTIONS
Remaining manual cleanup:

- State directory: ${STATE_DIR}
  Contains session history + activity log. Remove with:
      rm -rf "${STATE_DIR}"

- Tmux config: remove the claude-tmux source-file lines from
  ~/.tmux.conf (plain) or ~/.tmux.conf.local (oh-my-tmux).
  Reload with: prefix+r  (or: tmux source-file ~/.tmux.conf)

- Shell integration:
    oh-my-bash — drop 'claude-label' from the plugins array in ~/.bashrc
    plain bash/zsh — remove the 'source .../shell/claude-label.bash' line

Done.
INSTRUCTIONS
