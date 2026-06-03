#!/usr/bin/env bash
# setup.sh — single entrypoint for claude-tmux lifecycle operations.
#
#   ./setup.sh install      symlink bin/*, patch settings.json, wire shell
#   ./setup.sh uninstall    reverse the install
#   ./setup.sh doctor       run claude-tmux-doctor health check
#   ./setup.sh selftest     run tests/smoke.sh and tests/install-uninstall.sh
#   ./setup.sh help         this help
#
# Requirements: bash >= 4.0, jq. fzf / tmux are runtime deps; install preflight
# warns if they are missing.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
STATE_DIR="${CLAUDE_TMUX_STATE_DIR:-${HOME}/.local/state/claude-tmux}"
SETTINGS="${HOME}/.claude/settings.json"
OMB_PLUGIN_DIR="${HOME}/.oh-my-bash/custom/plugins/claude-label"

# Single source of truth for which scripts the integration ships.
EXECUTABLES=(
  claude-window-init
  claude-window-ask
  claude-window-status
  claude-window-restore
  claude-window-reset
  claude-window-subagent
  claude-window-notify
  claude-window-session
  claude-window-compact
  claude-window-summary
  claude-window-aggregate
  claude-window-pane
  claude-tmux-log
  claude-tmux-doctor
)

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

preflight() {
  (( BASH_VERSINFO[0] >= 4 )) \
    || die "bash >= 4.0 required (detected ${BASH_VERSION}). On macOS: brew install bash, then re-run with /opt/homebrew/bin/bash setup.sh."

  local missing=()
  for dep in jq fzf tmux; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
  done
  [ "${#missing[@]}" -eq 0 ] \
    || die "missing required dependencies: ${missing[*]}. Install via your package manager and retry."

  local v major minor
  v="$(tmux -V 2>/dev/null | awk '{print $2}')"
  major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%[^0-9]*}"
  if [ "${major:-0}" -lt 3 ] || { [ "${major:-0}" -eq 3 ] && [ "${minor:-0}" -lt 2 ]; }; then
    printf 'Warning: tmux >= 3.2 required for display-popup (detected %s); pickers will not work.\n' "$v" >&2
  fi

  # Warn on conflicting user bell-action setting.
  local c
  for c in "${HOME}/.tmux.conf" "${HOME}/.tmux.conf.local"; do
    [ -f "$c" ] || continue
    if grep -Eq '^[[:space:]]*set(-option|w|-window-option)?[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*bell-action[[:space:]]+(none|other)' "$c"; then
      printf 'Warning: %s sets bell-action to a value other than any; permission-prompt bells may not ring.\n' "$c" >&2
    fi
  done
}

cmd_install() {
  preflight

  printf 'Linking scripts...\n'
  mkdir -p "$BIN_DIR"
  for name in "${EXECUTABLES[@]}"; do
    local src="$REPO_DIR/bin/$name" target="$BIN_DIR/$name"
    [ -f "$src" ] || die "missing bin script: $src"
    chmod +x "$src"
    if [ -L "$target" ]; then
      rm "$target"
    elif [ -f "$target" ]; then
      printf '  [warn] replacing regular file with symlink: %s\n' "$target"
      rm "$target"
    fi
    ln -s "$src" "$target"
    printf '  linked: %s\n' "$target"
  done
  printf '\n'

  mkdir -p "$STATE_DIR"
  printf 'State directory: %s\n\n' "$STATE_DIR"

  install_hooks
  printf '\n'

  install_shell
  printf '\n'

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

Status-right aggregate (optional):
  #(${BIN_DIR}/claude-window-aggregate)

Reload: prefix+r (oh-my-tmux) or: tmux source-file ~/.tmux.conf

Run './setup.sh doctor' after reloading tmux to validate the install.
INSTRUCTIONS
}

install_hooks() {
  local hooks_json
  hooks_json=$(cat <<HOOKS
{
  "PreToolUse": [
    {"matcher": ".*",              "hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-init"}]},
    {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-ask"}]}
  ],
  "PostToolUse": [
    {"matcher": "TaskCreate|TaskUpdate", "hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-status"}]},
    {"matcher": ".*",                    "hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-restore"}]}
  ],
  "Notification": [{"hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-notify"}]}],
  "SubagentStop":  [{"hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-subagent"}]}],
  "SessionStart":  [{"hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-session"}]}],
  "PreCompact":    [{"hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-compact"}]}],
  "Stop":          [{"hooks": [{"type": "command", "command": "bash ${BIN_DIR}/claude-window-reset"}]}]
}
HOOKS
)

  mkdir -p "$(dirname "$SETTINGS")"
  [ -f "$SETTINGS" ] || printf '{}' > "$SETTINGS"

  local tmp
  tmp=$(mktemp)
  # Merge per-event so foreign hooks are preserved, while adding any newer
  # claude-tmux hooks that an older install lacks.
  jq --argjson h "$hooks_json" '
    def commands($items): [$items[]?.hooks[]?.command // empty];
    .hooks = (.hooks // {})
    | reduce ($h | to_entries[]) as $entry (
        .;
        .hooks[$entry.key] = (
          (.hooks[$entry.key] // []) as $existing
          | (commands($existing)) as $existing_commands
          | $existing + (
              $entry.value
              | map(
                  (commands([.])) as $candidate_commands
                  | select(all($candidate_commands[]; . as $cmd | ($existing_commands | index($cmd) | not)))
                )
            )
        )
      )
  ' "$SETTINGS" > "$tmp"
  if ! cmp -s "$SETTINGS" "$tmp"; then
    mv "$tmp" "$SETTINGS"
    printf 'Hooks merged into %s\n' "$SETTINGS"
  else
    rm "$tmp"
    printf 'Hooks already current in %s\n' "$SETTINGS"
  fi
}

install_shell() {
  if [ -d "${HOME}/.oh-my-bash" ]; then
    mkdir -p "$OMB_PLUGIN_DIR"
    local target="$OMB_PLUGIN_DIR/claude-label.plugin.bash"
    if [ -L "$target" ]; then
      rm "$target"
    elif [ -f "$target" ]; then
      printf '  [warn] replacing existing oh-my-bash plugin with symlink: %s\n' "$target"
      rm "$target"
    fi
    ln -s "$REPO_DIR/shell/claude-label.bash" "$target"
    printf 'oh-my-bash plugin linked: %s\n' "$target"
    if grep -q "claude-label" "${HOME}/.bashrc" 2>/dev/null; then
      printf "  'claude-label' already in plugins array — nothing to do.\n"
    else
      printf "  Add 'claude-label' to the plugins array in ~/.bashrc.\n"
    fi
  else
    printf 'Shell integration — add to ~/.bashrc or ~/.zshrc:\n'
    printf '  source %s/shell/claude-label.bash\n' "$REPO_DIR"
  fi
}

cmd_uninstall() {
  printf 'Removing bin symlinks...\n'
  local removed=0 name target
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

  target="$OMB_PLUGIN_DIR/claude-label.plugin.bash"
  if [ -L "$target" ] || [ -f "$target" ]; then
    rm "$target"
    rmdir "$OMB_PLUGIN_DIR" 2>/dev/null || true
    printf 'Removed oh-my-bash plugin: %s\n\n' "$target"
  fi

  if [ -f "$SETTINGS" ]; then
    if ! command -v jq >/dev/null 2>&1; then
      printf 'Warning: jq not found — skipping %s hook cleanup.\n' "$SETTINGS" >&2
      printf '         Remove any line containing claude-window- by hand.\n\n' >&2
    else
      local tmp
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
INSTRUCTIONS
}

cmd_doctor() {
  exec "$REPO_DIR/bin/claude-tmux-doctor" "$@"
}

cmd_selftest() {
  bash "$REPO_DIR/tests/smoke.sh"
  bash "$REPO_DIR/tests/install-uninstall.sh"
}

cmd_help() {
  sed -n '2,10p' "$0"
}

cmd="${1:-help}"
shift || true
case "$cmd" in
  install)   cmd_install "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  doctor)    cmd_doctor "$@" ;;
  selftest)  cmd_selftest "$@" ;;
  help|-h|--help) cmd_help ;;
  *) printf 'Unknown command: %s\n\n' "$cmd" >&2; cmd_help >&2; exit 2 ;;
esac
