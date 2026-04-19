# claude-label — sets CLAUDE_WINDOW_LABEL and renames the current tmux window
# Source this file from ~/.bashrc or ~/.zshrc:
#   source /path/to/claude-tmux/shell/claude-label.bash
#
# oh-my-bash users can symlink into custom plugins:
#   ~/.oh-my-bash/custom/plugins/claude-label/claude-label.plugin.bash

claude-label() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "Usage: claude-label <name>" >&2
    return 1
  fi
  export CLAUDE_WINDOW_LABEL="$name"
  if [ -n "${TMUX:-}" ]; then
    tmux rename-window "○ ${name}" 2>/dev/null || true
  fi
}
