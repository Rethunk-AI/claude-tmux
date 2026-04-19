#!/usr/bin/env bash
# install.sh — install claude-tmux on a new machine
#
# What this does:
#   1. Symlinks bin/* to ~/.local/bin/ (idempotent)
#   2. Creates ~/.local/state/claude-tmux/ for persistent state + logs
#   3. Patches ~/.claude/settings.json with hooks (skipped if already installed)
#   4. Wires shell/claude-label.bash as oh-my-bash plugin or prints source line
#   5. Prints tmux config instructions
#
# Requirements: bash >= 4.0, jq, fzf, tmux >= 3.2

set -euo pipefail

# --- 0. Preflight ---

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'Error: bash >= 4.0 required (detected %s).\n' "$BASH_VERSION" >&2
  printf 'macOS stock bash is 3.2. Install a newer bash (e.g. `brew install bash`)\n' >&2
  printf 'and re-run with /opt/homebrew/bin/bash install.sh or /usr/local/bin/bash install.sh.\n' >&2
  exit 1
fi

missing=()
for dep in jq fzf tmux; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Error: missing required dependencies: %s\n' "${missing[*]}" >&2
  printf 'Install them via your package manager (apt, brew, dnf, …) and retry.\n' >&2
  exit 1
fi

if command -v tmux >/dev/null 2>&1; then
  tmux_version="$(tmux -V 2>/dev/null | awk '{print $2}')"
  tmux_major="${tmux_version%%.*}"
  tmux_minor="${tmux_version#*.}"; tmux_minor="${tmux_minor%%[^0-9]*}"
  if [ "${tmux_major:-0}" -lt 3 ] || { [ "${tmux_major:-0}" -eq 3 ] && [ "${tmux_minor:-0}" -lt 2 ]; }; then
    printf 'Warning: tmux >= 3.2 required for display-popup (detected %s).\n' "$tmux_version" >&2
    printf 'Pickers (prefix+f, prefix+P) will not work without it.\n' >&2
  fi
fi

# Detect a conflicting user bell-action setting (claude-tmux needs `any`).
for _conf in "${HOME}/.tmux.conf" "${HOME}/.tmux.conf.local"; do
  [ -f "$_conf" ] || continue
  # shellcheck disable=SC2016
  if grep -Eq '^[[:space:]]*set(-option|w|-window-option)?[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*bell-action[[:space:]]+(none|other)' "$_conf"; then
    printf 'Warning: %s sets bell-action to a value other than `any`.\n' "$_conf" >&2
    printf '         Permission-prompt bells may not ring. Override or remove that line;\n' >&2
    printf '         our tmux/settings.conf expects `set -g bell-action any`.\n' >&2
  fi
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
STATE_DIR="${CLAUDE_TMUX_STATE_DIR:-${HOME}/.local/state/claude-tmux}"
SETTINGS="${HOME}/.claude/settings.json"

# Executables only — claude-window-lib is a sourced library, not a script
EXECUTABLES=(
  "$REPO_DIR"/bin/claude-window-init
  "$REPO_DIR"/bin/claude-window-ask
  "$REPO_DIR"/bin/claude-window-status
  "$REPO_DIR"/bin/claude-window-restore
  "$REPO_DIR"/bin/claude-window-reset
  "$REPO_DIR"/bin/claude-window-subagent
  "$REPO_DIR"/bin/claude-window-notify
  "$REPO_DIR"/bin/claude-window-summary
  "$REPO_DIR"/bin/claude-window-aggregate
  "$REPO_DIR"/bin/claude-window-pane
  "$REPO_DIR"/bin/claude-tmux-log
  "$REPO_DIR"/bin/claude-tmux-doctor
)

# --- 1. Symlink bin/ scripts ---

echo "Linking scripts..."
mkdir -p "$BIN_DIR"
chmod +x "${EXECUTABLES[@]}"

for script in "${EXECUTABLES[@]}"; do
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

# --- 2. Create state directory ---

mkdir -p "$STATE_DIR"
echo "State directory: $STATE_DIR"
echo ""

# --- 3. Patch ~/.claude/settings.json ---

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
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

# Check if our hooks are already installed (any command referencing claude-window-)
already_installed=false
if jq -e '
  .hooks // {} |
  [to_entries[] | .value[] | .hooks // [] | .[] | .command] |
  any(contains("claude-window-"))
' "$SETTINGS" >/dev/null 2>&1; then
  already_installed=true
fi

if $already_installed; then
  echo "Hooks already present in $SETTINGS — skipping."
elif jq -e '.hooks' "$SETTINGS" >/dev/null 2>&1; then
  # hooks block exists but not ours — merge per-event to avoid clobbering existing hooks
  tmp=$(mktemp)
  jq --argjson h "$HOOKS_JSON" '
    .hooks as $existing |
    reduce ($h | to_entries[]) as $entry (
      .;
      .hooks[$entry.key] = (($existing[$entry.key] // []) + $entry.value)
    )
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Hooks merged into existing hooks block in $SETTINGS"
else
  tmp=$(mktemp)
  jq --argjson h "$HOOKS_JSON" '. + {hooks: $h}' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Hooks added to $SETTINGS"
fi

echo ""

# --- 4. Shell integration (claude-label) ---

OMB_PLUGIN_DIR="${HOME}/.oh-my-bash/custom/plugins/claude-label"
if [ -d "${HOME}/.oh-my-bash" ]; then
  mkdir -p "$OMB_PLUGIN_DIR"
  target="$OMB_PLUGIN_DIR/claude-label.plugin.bash"
  if [ -L "$target" ]; then
    rm "$target"
  elif [ -f "$target" ]; then
    echo "  [warn] Replacing existing oh-my-bash plugin with symlink: $target"
    rm "$target"
  fi
  ln -s "$REPO_DIR/shell/claude-label.bash" "$target"
  echo "oh-my-bash plugin linked: $target"
  if grep -q "claude-label" "${HOME}/.bashrc" 2>/dev/null; then
    echo "  'claude-label' already in plugins array — nothing to do."
  else
    echo "  Add 'claude-label' to the plugins array in ~/.bashrc."
  fi
else
  echo "Shell integration — add to ~/.bashrc or ~/.zshrc:"
  echo "  source ${REPO_DIR}/shell/claude-label.bash"
fi

echo ""

# --- 5. Instructions ---

cat <<INSTRUCTIONS
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

Status-right aggregate (optional) — add to tmux status-right:
  #(${BIN_DIR}/claude-window-aggregate)

Reload tmux config: prefix+r (oh-my-tmux) or: tmux source-file ~/.tmux.conf

Done.
INSTRUCTIONS
