# Claude Code entrypoint

All LLM onboarding lives in **[`AGENTS.md`](AGENTS.md)**. This file exists so Claude Code discovers project context automatically; do not duplicate content here.

## Key gotcha

All scripts source the shared lib via a **relative path** (`${BASH_SOURCE[0]%/*}/claude-window-lib`). When editing or adding scripts, never hardcode an absolute path to the lib.
