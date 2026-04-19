# Security policy

## Reporting a vulnerability

Do **not** open a public GitHub issue for security vulnerabilities.

Report privately to: **damon.blais@gmail.com**

Include:
- Description of the vulnerability and potential impact
- Steps to reproduce
- Affected version (commit SHA or tag)

You will receive an acknowledgement within 72 hours. We aim to resolve confirmed vulnerabilities within 14 days of initial report.

## Scope

claude-tmux runs locally as the invoking user. It:
- Writes state files to `~/.local/state/claude-tmux/`
- Reads/writes `~/.claude/settings.json` (install.sh only)
- Invokes `tmux`, `jq`, `fzf`, and `notify-send`
- Does **not** make network requests
- Does **not** store credentials or secrets

Findings most relevant to this project: command injection in script arguments, unsafe temp-file handling, or privilege escalation via symlink attacks on state files.
