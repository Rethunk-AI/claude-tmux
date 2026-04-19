#!/usr/bin/env bash
# install.sh — install claude-tmux on a new machine
#
# What this does:
#   1. Symlinks bin/* to ~/.local/bin/ (idempotent)
#   2. Patches ~/.claude/settings.json with the hooks block (if no hooks block exists)
#      If a hooks block already exists, prints manual merge instructions.
#   3. Prints shell integration and tmux config instructions.
#
# Requirements: bash >= 4.0, jq, fzf, tmux >= 3.2

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SETTINGS="${HOME}/.claude/settings.json"

# --- 1. Symlink bin/ scripts ---

mkdir -p "$BIN_DIR"
chmod +x "$REPO_DIR"/bin/claude-window-*

for script in "$REPO_DIR"/bin/claude-window-*; do
  name="$(basename "$script")"
  target="$BIN_DIR/$name"
  if [ -L "$target" ]; then
    rm "$target"
  elif [ -f "$target" ]; then
    echo "  [warn] Replacing existing file with symlink: $target"
    rm "$target"
  fi
  ln -s "$script" "$target"
  echo "  linked: $target"
done

echo ""

# --- 2. Patch ~/.claude/settings.json ---

HOOKS_JSON=$(cat <<'HOOKS'
{
  "PreToolUse": [
    {"matcher": ".*",              "hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-init"}]},
    {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-ask"}]}
  ],
  "PostToolUse": [
    {"matcher": "TaskCreate|TaskUpdate", "hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-status"}]},
    {"matcher": ".*",                    "hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-restore"}]}
  ],
  "Notification": [{"hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-notify"}]}],
  "SubagentStop":  [{"hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-subagent"}]}],
  "Stop":          [{"hooks": [{"type": "command", "command": "bash ~/.local/bin/claude-window-reset"}]}]
}
HOOKS
)

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

if jq -e '.hooks' "$SETTINGS" >/dev/null 2>&1; then
  echo "Hooks block already present in $SETTINGS."
  echo "Merge manually — expected hooks JSON:"
  echo ""
  printf '%s\n' "$HOOKS_JSON" | jq .
  echo ""
  echo "Or run: jq '.hooks = (.hooks + \$h)' --argjson h '$HOOKS_JSON' $SETTINGS > /tmp/settings.json && mv /tmp/settings.json $SETTINGS"
else
  tmp=$(mktemp)
  jq --argjson h "$HOOKS_JSON" '. + {hooks: $h}' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Hooks added to $SETTINGS"
fi

echo ""

# --- 3. Instructions ---

cat <<INSTRUCTIONS
Shell integration — add to ~/.bashrc or ~/.zshrc:
  source ${REPO_DIR}/shell/claude-label.bash

Tmux config — choose one:

  Plain tmux (~/.tmux.conf):
    source-file ${REPO_DIR}/tmux/settings.conf
    source-file ${REPO_DIR}/tmux/bindings.conf
    source-file ${REPO_DIR}/tmux/plain-tmux.conf

  oh-my-tmux (~/.tmux.conf.local):
    Copy relevant sections from:
    ${REPO_DIR}/tmux/oh-my-tmux.conf
    ${REPO_DIR}/tmux/settings.conf
    ${REPO_DIR}/tmux/bindings.conf

Reload tmux config: prefix+r (oh-my-tmux) or: tmux source-file ~/.tmux.conf

Done.
INSTRUCTIONS
