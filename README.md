# Claude Worktrees

Multi-agent development environment using git worktrees and screen sessions.

## Overview

Claude Worktrees allows you to run multiple Claude Code instances simultaneously, each working on a different feature branch using git worktrees. A coordinator manages integration while workers develop in parallel.

```
┌─────────────────────────────────────────────────────────────┐
│                     SCREEN SESSION                          │
├──────────┬──────────────────┬───────────────────────────────┤
│ Window   │ Branch           │ Role                          │
├──────────┼──────────────────┼───────────────────────────────┤
│ coord    │ dev (base)       │ Merge, deploy, orchestrate    │
│ qa       │ dev (base)       │ Test, review (no own branch)  │
├──────────┼──────────────────┼───────────────────────────────┤
│ front    │ feat/xxx-front   │ Frontend development          │
│ back     │ feat/xxx-back    │ Backend development           │
│ sec      │ feat/xxx-sec     │ Security features             │
└──────────┴──────────────────┴───────────────────────────────┘
```

## Installation

```bash
git clone https://github.com/yourusername/claude-worktrees.git
cd claude-worktrees
./install.sh
```

Or manually:

```bash
# Add to PATH
export PATH="$HOME/.local/bin:$PATH"

# Create alias
alias cwt='/path/to/claude-worktrees/bin/cwt'
```

## Usage

### Interactive Mode

```bash
cd your-repo
cwt
```

This will prompt for:
1. **Base branch** - Integration branch (main, dev, etc.)
2. **Type** - feat, fix, refactor, hot, docs, test, chore
3. **Feature name** - Name for this work
4. **Workers** - Template (wt1,wt2,wt3) or custom (front,back,sec)
5. **QA** - Include QA window?

### Quick Mode

```bash
cwt feat/new-dashboard              # Use defaults
cwt --base dev feat/api-refactor    # Specify base branch
cwt --template front,back,sec feat/ui
```

### Commands

```bash
cwt                 # Start interactive mode
cwt --help          # Show help
cwt --list          # List active sessions
cwt --kill          # Kill current session
```

### Screen Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+a n` | Next window |
| `Ctrl+a p` | Previous window |
| `Ctrl+a 0-9` | Go to window N |
| `Ctrl+a "` | List windows |
| `Ctrl+a d` | Detach (keep running) |

### Inter-agent Messaging

```bash
wt-msg send front "Review the API changes"
wt-msg broadcast "Starting integration tests"
wt-msg check       # Check for messages
wt-msg read        # Read messages
wt-msg status      # Show status
```

## Workflow

### 1. Start Session

```bash
cd my-project
cwt
# Select: dev, feat, new-feature, front/back/sec, yes
```

### 2. Workers Develop

Each worker develops in their worktree:
```
worktree-feat-new-feature-front/  → feat/new-feature-front
worktree-feat-new-feature-back/   → feat/new-feature-back
```

### 3. Notify Coordinator

When ready for merge:
```bash
wt-msg send coord "front ready for merge"
```

### 4. Coordinator Merges

In coord window:
```bash
git merge feat/new-feature-front
git merge feat/new-feature-back
```

### 5. QA Tests

QA tests the integrated code on the base branch.

## Branch Naming Convention

Following [Conventional Commits](https://www.conventionalcommits.org/):

| Type | Description |
|------|-------------|
| `feat/` | New feature |
| `fix/` | Bug fix |
| `hot/` | Hotfix |
| `refactor/` | Code refactoring |
| `docs/` | Documentation |
| `test/` | Tests |
| `chore/` | Maintenance |

Branch format: `{type}/{feature-name}-{worker}`

Examples:
- `feat/dashboard-front`
- `fix/auth-api`
- `refactor/database-wt1`

## Project Structure

```
claude-worktrees/
├── bin/
│   ├── cwt           # Main launcher
│   └── pulser        # Idle monitor
├── lib/
│   └── wt-msg        # Messaging utility
├── hooks/            # Claude Code hooks
├── templates/        # Config templates
├── install.sh        # Installation script
└── README.md
```

## Requirements

- git
- screen
- jq
- Claude Code CLI

## License

MIT
