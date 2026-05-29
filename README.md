# claude-tmux

Hook-driven tmux integration for Claude Code. Surfaces agent state in window tab titles, rings an audible bell on permission prompts, and provides a fuzzy session picker across all Claude windows.

```
▶ 2/5 ironlaw-network   ← tasks in progress (2 of 5 done)
✓ 5/5 ironlaw-network   ← all tasks complete
■ 5/5 ironlaw-network   ← session stopped
! 2/5 ironlaw-network   ← waiting for permission (bell rings)
? 2/5 ironlaw-network   ← waiting for AskUserQuestion
· 2/5 ironlaw-network   ← idle prompt shown
↩ 2/5 ironlaw-network   ← subagent just returned
⟳ 2/5 ironlaw-network   ← compacting context
○ bastion               ← idle, no tasks
```

Pure bash, no build step. Requires tmux ≥ 3.2, bash ≥ 4.0, `jq`, `fzf`, and Claude Code.

## Repository layout

```
bin/        hook scripts + pickers + doctor + activity-log viewer
shell/      claude-label function (plain + oh-my-bash)
tmux/       settings / bindings / per-flavor status-right configs
specs/      record of requirements and design decisions
tests/      smoke harness + install/uninstall harness
setup.sh    single entrypoint: setup.sh {install|uninstall|doctor|selftest}
```

## Documentation

- [`HUMANS.md`](./HUMANS.md) — install, tmux/shell config, usage, env vars, verify
- [`AGENTS.md`](./AGENTS.md) — developer / LLM onboarding, hook wiring, state-file model
- [`specs/done/claude-tmux/spec.md`](./specs/done/claude-tmux/spec.md) — requirements (CT1–CT29) and design decisions
- [`CHANGELOG.md`](./CHANGELOG.md) — release notes
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — commit conventions, bash style, PR checklist
- [`SECURITY.md`](./SECURITY.md) — disclosure policy
