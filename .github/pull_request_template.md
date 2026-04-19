## Summary

<!-- What changed and why. Keep short. -->

## Checklist

- [ ] **Shell safety** — scripts use `set -euo pipefail`; no hardcoded state paths (use `cw_state_dir()`); lib sourced via `${BASH_SOURCE[0]%/*}/claude-window-lib`
- [ ] **Idempotency** — `install.sh` tested twice in a row without errors or duplicate entries
- [ ] **Golden path** — task create → progress → complete → stop exercised manually in tmux
- [ ] **Docs** — README / AGENTS.md / HUMANS.md updated if behavior or env vars changed
