#! bash oh-my-bash.module
# claude-label — sets CLAUDE_WINDOW_LABEL and renames the current tmux window
#
# Plain bash/zsh: source this file from ~/.bashrc or ~/.zshrc
# oh-my-bash: install.sh symlinks this file as claude-label.plugin.bash;
#             add 'claude-label' to the plugins array in ~/.bashrc

claude-label() {
  local name="${1:-}"
  if [ $# -eq 0 ]; then
    unset CLAUDE_WINDOW_LABEL
    if [ -n "${TMUX:-}" ]; then
      tmux rename-window "○ $(basename "$PWD")" 2>/dev/null || true
    fi
    return 0
  fi
  export CLAUDE_WINDOW_LABEL="$name"
  if [ -n "${TMUX:-}" ]; then
    tmux rename-window "○ ${name}" 2>/dev/null || true
  fi
}
