# Contributing

## Scope

claude-tmux is a personal-workflow tool for the Rethunk-AI organization. External contributions are welcome as issues or discussions; PRs will be reviewed on a best-effort basis.

## Pull requests

claude-tmux is a personal-workflow tool. External PRs are reviewed on a best-effort basis.

1. **Fork and branch** — create a branch with a descriptive name (`fix/counter-clamp`, `feat/bell-options`).
2. **One logical change per PR** — keep the diff focused; large rewrites will be asked to split.
3. **All tests green** — run `./setup.sh selftest` before opening the PR. CI runs shellcheck + smoke + install/uninstall automatically on push.
4. **PR description** — state what the change does and why. Reference any related issue.
5. **No external dependencies** — new scripts must stay within the declared prerequisites (`tmux`, `jq`, `fzf`, bash ≥ 4.0).

Review turnaround is not guaranteed. If you need a quick response, open an issue first.

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

Scope is the script or area: `lib`, `init`, `status`, `reset`, `notify`, `ask`, `subagent`, `restore`, `aggregate`, `log`, `setup`, `doctor`, `spec`, `readme`.

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

Automated: `./setup.sh selftest` runs `tests/smoke.sh` and `tests/install-uninstall.sh`. CI runs both on every push via `.github/workflows/shellcheck.yml`.

Manual golden-path verify (anything UI/tmux-visible the harnesses can't assert):

1. Run `./setup.sh install` twice from a clean checkout; confirm idempotency.
2. Open a Claude session inside tmux; exercise the golden path (task create → progress → complete → stop).
3. Trigger a permission prompt; confirm the `!` title + bell.
4. Open `prefix+f`; confirm the session appears in the picker.
5. Check `claude-tmux-log` for the activity entry after stop.
6. Run `./setup.sh doctor`; confirm zero failures.
