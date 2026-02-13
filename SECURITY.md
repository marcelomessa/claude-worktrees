# Security Policy

## Important Notice

CWT orchestrates multiple AI agents that execute shell commands with elevated
permissions (`--dangerously-skip-permissions`). While safety hooks are included,
this software is provided "as is" with no warranties or guarantees.

## Built-in Safety Mechanisms

- **bash-validator hook**: Blocks destructive commands (rm -rf /, git reset --hard, etc.)
- **Worker restrictions**: Workers cannot push, merge, or deploy
- **File protector**: Blocks editing of critical config files
- **Session overrides**: Temporary allow/block rules per session

## Reporting a Vulnerability

If you discover a security vulnerability:

1. **Do NOT open a public issue**
2. Open a private security advisory on GitHub
3. Or email: mrmessa@gmail.com

Response is best-effort. This is a free, open-source project maintained
in spare time.

## Support

This project is provided as-is under the MIT license. There are no support
guarantees. Issues and PRs are welcome but addressed on a best-effort basis.
