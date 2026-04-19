# Contributing

## Scope

claude-tmux is a personal-workflow tool for the Rethunk-AI organization. External contributions are welcome as issues or discussions; PRs will be reviewed on a best-effort basis.

## Conventions

### Commits

Conventional commits: `type(scope): subject`

| Type | When |
|------|------|
| `feat` | New capability or hook |
| `fix` | Bug in existing behavior |
| `chore` | Install, config, or tooling |
| `docs` | README, AGENTS.md, HUMANS.md, spec |
| `refactor` | Internal restructure, no behavior change |

Scope is the script or area: `lib`, `init`, `status`, `reset`, `notify`, `ask`, `subagent`, `restore`, `aggregate`, `log`, `install`, `spec`, `readme`.

Body: explain WHY, not what. One logical unit per commit.

### Bash style

- `set -euo pipefail` in every top-level script.
- Source the shared lib via `source "${BASH_SOURCE[0]%/*}/claude-window-lib"` — never hardcode a path.
- Use `${TMUX_PANE:-}` and `${TMUX:-}` guard checks before any `tmux` invocation.
- Prefer `printf` over `echo` for portability.
- No external dependencies beyond `tmux`, `jq`, and `fzf` (which are declared prerequisites).

### No build step

Pure bash — no compilation, no package manager. Scripts run directly from `bin/`.

## Testing changes

There is no automated test suite. Before opening a PR:

1. Run `./install.sh` from a clean checkout; confirm idempotency on a second run.
2. Open a Claude session inside tmux; exercise the golden path (task create → progress → complete → stop).
3. Trigger a permission prompt and confirm the `!` title + bell.
4. Open `prefix+f` and confirm the session appears in the picker.
5. Check `claude-tmux-log` for the activity entry after stop.
