# Contributing to CWT

Thank you for your interest in contributing to Claude WorkTrees!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/claude-worktrees.git`
3. Create a feature branch: `git checkout -b feature/my-feature`
4. Make your changes
5. Test locally: `./install.sh && cwt --help`
6. Commit with conventional commits: `git commit -m "feat: add new feature"`
7. Push and open a Pull Request

## Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/claude-worktrees.git
cd claude-worktrees
./install.sh
```

### Requirements

- zsh or Bash 3.2+
- Git 2.5+ (worktree support)
- tmux 3.0+
- jq
- Node.js 18+ (for daemon/MCP server)
- Claude Code CLI (`claude`)

## Code Guidelines

- **Shell scripts**: Use `#!/bin/bash`, validate with `bash -n`
- **Commit messages**: Follow [Conventional Commits](https://www.conventionalcommits.org/)
  - `feat:` new features
  - `fix:` bug fixes
  - `docs:` documentation
  - `refactor:` code restructuring
- **No secrets**: Never commit API keys, tokens, or personal paths
- **Test your changes**: Run `bash -n` on all modified `.sh` files

## Pull Request Process

1. Ensure your branch is up to date with `main`
2. All CI checks must pass (shellcheck, syntax validation)
3. PRs require at least one review approval
4. Squash merge is preferred for clean history

## Reporting Issues

- Use GitHub Issues
- Include your OS, bash version, tmux version
- Include relevant logs from `.cwt/logs/`

## Code of Conduct

Be respectful and constructive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/).
