# Claude Worktrees (CWT)

Multi-agent Claude Code environment using git worktrees and tmux sessions.

## What are Git Worktrees?

Git worktrees allow you to have **multiple working directories** from the same repository, each checked out to a different branch simultaneously.

### Worktrees vs Branches

| Aspect | Branches | Worktrees |
|--------|----------|-----------|
| **Disk** | Single working directory | Multiple directories, one per branch |
| **Switching** | `git checkout` changes files in place | Each worktree is independent |
| **Parallel work** | Cannot edit two branches at once | Edit multiple branches simultaneously |
| **Conflicts** | Stash/commit before switching | No conflicts between worktrees |
| **Use case** | Sequential development | Parallel multi-agent development |

```
Traditional (branches):
my-project/
├── .git/
└── src/          ← checkout main OR feature, never both

Worktrees:
my-project/                    ← main branch (coordinator)
├── .git/
└── src/

workspace-frontend/            ← feature/frontend branch
├── .git → ../my-project/.git  (linked)
└── src/

workspace-backend/             ← feature/backend branch
├── .git → ../my-project/.git  (linked)
└── src/
```

**Key benefit**: Each Claude instance works in its own directory with its own branch, no file conflicts, true parallel development.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      TMUX SESSION (cwt)                         │
├─────────────────────────────────────────────────────────────────┤
│  Window 0: COORDINATOR                                          │
│  ├── Branch: main/dev (integration)                             │
│  ├── Role: Plan, merge, deploy, orchestrate                     │
│  └── Uses: subagents (Explore, Plan) as threads                 │
├─────────────────────────────────────────────────────────────────┤
│  Window 1: WORKER frontend                                      │
│  ├── Worktree: workspace-frontend/                              │
│  ├── Branch: feature/frontend                                   │
│  └── Role: Frontend development                                 │
├─────────────────────────────────────────────────────────────────┤
│  Window 2: WORKER backend                                       │
│  ├── Worktree: workspace-backend/                               │
│  ├── Branch: feature/backend                                    │
│  └── Role: Backend development                                  │
├─────────────────────────────────────────────────────────────────┤
│  Window 3: WORKER security                                      │
│  ├── Worktree: workspace-security/                              │
│  ├── Branch: feature/security                                   │
│  └── Role: Security features                                    │
├─────────────────────────────────────────────────────────────────┤
│  Window N: MONITOR                                              │
│  └── Status dashboard                                           │
└─────────────────────────────────────────────────────────────────┘
```

### Communication Flow

```
                    ┌─────────────┐
                    │ COORDINATOR │
                    │  (main/)    │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ frontend │    │ backend  │    │ security │
    │ (core 1) │    │ (core 2) │    │ (core 3) │
    └──────────┘    └──────────┘    └──────────┘

Communication via shared state file:
  Project mode:  .cwt/state.json (isolated per project)
  Legacy mode:   /tmp/claude-wt-state.json (global)
```

## Installation

```bash
git clone https://github.com/marcelomessa/claude-worktrees.git
cd claude-worktrees
./install.sh
```

This installs to `~/.local/bin/`:
- `cwt` - Main launcher
- `wt-msg` - Inter-agent messaging
- `wt-task` - Task assignment
- `wt-init` - Worktree creation

## Project-Based Setup (Recommended)

The recommended way to use CWT is with a **project folder** that contains all repos/worktrees:

```
~/projects/my-project/        # Project folder (not a repo)
├── .cwt/                     # CWT state (isolated)
│   ├── config.json
│   └── state.json
├── main/                     # Coordinator (cloned repo)
│   └── .git/
├── feature-frontend/         # Worker (worktree)
│   └── .git → ../main/.git
├── feature-backend/          # Worker (worktree)
│   └── .git → ../main/.git
└── docs/                     # Worker (separate repo)
    └── .git/
```

### Step 1: Create Project

```bash
mkdir -p ~/projects/my-project
cd ~/projects/my-project
cwt init --name my-project
```

### Step 2: Clone Repo and Create Worktrees

```bash
# Clone main repo
git clone git@github.com:user/repo.git main
cd main

# Create worktrees INSIDE project folder
git worktree add ../feature-frontend -b feature/frontend
git worktree add ../feature-backend -b feature/backend

# Optional: add separate repo
cd ..
git clone git@github.com:user/docs.git docs
```

### Step 3: Start Session

```bash
cd ~/projects/my-project
cwt    # Auto-detects repos and worktrees

# Or specify workers:
cwt feature-frontend feature-backend docs
```

### Multi-Project Support

Each project has its own tmux session and isolated state:

```bash
# Terminal 1: Project A
cd ~/projects/project-a && cwt
# Session: cwt-project-a

# Terminal 2: Project B
cd ~/projects/project-b && cwt
# Session: cwt-project-b

# List all CWT sessions
cwt --list-all
```

## Legacy Setup (Worktrees as Siblings)

For existing setups where worktrees are siblings of the main repo:

```bash
cd my-existing-project

# Create worktrees for each worker
git worktree add ../workspace-frontend -b feature/frontend
git worktree add ../workspace-backend -b feature/backend
git worktree add ../workspace-security -b feature/security
```

Or use the helper:

```bash
wt-init frontend backend security
# Creates: workspace-frontend/, workspace-backend/, workspace-security/
```

Start the session:

```bash
cwt frontend backend security
```

Or let CWT detect worktrees automatically:

```bash
cwt   # Detects existing worktrees
```

> Note: Legacy mode uses global state in `/tmp/`. For isolated multi-project work, use the project-based setup above.

## Permissionless Mode (Critical)

CWT runs Claude with `--dangerously-skip-permissions` to enable autonomous operation without confirmation prompts.

### Why This Mode?

- **Multi-agent**: Each Claude operates independently, can't wait for human confirmation
- **Parallel work**: Workers must act autonomously
- **Efficiency**: No blocking on permission dialogs

### Safety Measures

Since permission checks are bypassed, safety is enforced via:

1. **CLAUDE.md templates** - Instructions that Claude follows
2. **Prohibited commands list** - Destructive operations blocked by convention
3. **Worktree isolation** - Each worker in separate directory
4. **Coordinator control** - Only coordinator merges/deploys

### Risks

- Workers CAN execute any command
- Relies on Claude following CLAUDE.md instructions
- Always review changes before merging

## Prohibited Operations (Workers)

Workers must NEVER execute these commands:

### Git Destructive
```bash
git add -A              # Use: git add <specific files>
git add .               # Use: git add <specific files>
git reset --hard        # PROHIBITED - code loss
git checkout -- .       # PROHIBITED - code loss
git clean -fd           # PROHIBITED - file loss
git merge               # PROHIBITED - coordinator does merges
git rebase              # PROHIBITED - coordinator does rebases
git push --force        # PROHIBITED
git push                # Only coordinator pushes
```

### Deployment (Coordinator Only)
```bash
azion deploy            # PROHIBITED - coordinator deploys
azion update            # PROHIBITED - coordinator updates
azion delete            # PROHIBITED
npm publish             # PROHIBITED
```

### Process Management
```bash
kill                    # PROHIBITED - may kill other workers
pkill                   # PROHIBITED
killall                 # PROHIBITED
```

### Allowed Operations
```bash
# Safe git
git add <specific-file>
git commit -m "message"
git status
git diff
git log
git stash

# Development
npm run dev
npm run build
npm test

# Reading
cat, head, tail, grep, ls, find
```

## Usage

### Initialize Project

```bash
cwt init                    # Initialize in current directory
cwt init --name my-project  # With custom name
```

### Start New Session

```bash
cwt frontend backend security    # Named workers
cwt -c frontend backend          # Resume previous Claude sessions (--continue)
cwt                              # Auto-detect repos/worktrees
```

### Manage Session

```bash
cwt --list      # List session for current project
cwt --list-all  # List ALL CWT sessions (all projects)
cwt --status    # Show windows
cwt --kill      # End session for current project
cwt             # Reconnect to existing session
```

### Tmux Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+b n` | Next window |
| `Ctrl+b p` | Previous window |
| `Ctrl+b 0-9` | Go to window N |
| `Ctrl+b w` | List windows |
| `Ctrl+b d` | Detach (keeps running) |

### Mouse/Trackpad

| Action | Effect |
|--------|--------|
| Scroll | Navigate history (scrollback) |
| Click | Select pane/window |
| `q` or `Esc` | Exit scroll mode |

### Inter-Agent Communication

```bash
# Send message
wt-msg send frontend "Implement the login form"
wt-msg send coord "Task completed, ready for merge"

# Broadcast to all
wt-msg broadcast "Breaking change in API"

# Check messages
wt-msg check        # Count pending
wt-msg read         # Read messages
wt-msg status       # Overview

# Assign task
wt-task frontend "Create user registration component"
wt-task backend "Add /api/users endpoint"
```

## Workflow

### 1. Planning Phase (Coordinator)

```bash
# Coordinator uses subagents to plan
# Breaks feature into worker tasks
# Sends tasks to workers
wt-task frontend "Implement login UI"
wt-task backend "Create auth API"
wt-task security "Add input validation"
```

### 2. Development Phase (Workers)

Each worker:
1. Receives task via `wt-msg read`
2. Uses subagents (Explore, Plan) to understand scope
3. Implements changes in their worktree
4. Commits to their feature branch
5. Notifies coordinator: `wt-msg send coord "login UI done"`

### 3. Integration Phase (Coordinator)

```bash
# Coordinator merges branches
git merge feature/frontend
git merge feature/backend
git merge feature/security

# Resolves conflicts
# Runs tests
# Deploys
```

## File Structure

```
claude-worktrees/
├── bin/
│   ├── cwt                 # Main launcher
│   ├── cwt-screen          # Screen version (legacy)
│   ├── tmux-launcher.sh    # Tmux session creator
│   └── tmux-pulser.sh      # Idle worker monitor
├── lib/
│   ├── wt-msg              # Messaging between agents
│   ├── wt-task             # Task assignment
│   ├── wt-init             # Worktree creation helper
│   └── wt-setup            # Environment setup
├── config/
│   ├── tmux.conf           # Tmux configuration (mouse, colors)
│   └── screenrc            # Screen configuration (legacy)
├── templates/
│   ├── CLAUDE.coord.md     # Coordinator instructions
│   └── CLAUDE.worker.md    # Worker instructions
├── hooks/
│   ├── init-worker.sh      # Worker initialization hook
│   └── statusline.sh       # Status bar hook
├── install.sh              # Installation script
└── README.md
```

## Logs

All sessions are logged to `~/repos/terminal_logs/`:

```
cwt-coordinator-20241231-143022.log
cwt-frontend-20241231-143022.log
cwt-backend-20241231-143022.log
```

## Requirements

- git (with worktree support, 2.5+)
- tmux
- jq
- Claude Code CLI

## Configuration

### Custom Log Directory

```bash
export CWT_LOG_DIR=/path/to/logs
cwt frontend backend
```

### Custom Project Directory

```bash
CWT_PROJECT=/path/to/repo cwt frontend backend
```

## Troubleshooting

### "Session already exists"

```bash
cwt --kill    # End existing session
cwt           # Start fresh
```

### Workers Not Seeing Messages

Check message directory permissions:
```bash
ls -la /tmp/claude-wt-messages/
```

### Worktree Not Found

Verify worktrees exist:
```bash
git worktree list
```

Create if missing:
```bash
git worktree add ../workspace-name -b feature/name
```

## License

MIT
