#! bash oh-my-bash.module
# claude-label — sets CLAUDE_WINDOW_LABEL and renames the current tmux window
#
# Plain bash/zsh: source this file from ~/.bashrc or ~/.zshrc
# oh-my-bash: install.sh symlinks this file as claude-label.plugin.bash;
#             add 'claude-label' to the plugins array in ~/.bashrc

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
