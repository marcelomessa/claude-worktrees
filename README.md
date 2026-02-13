# Claude Worktrees (CWT)

Run multiple Claude Code agents in parallel, each with isolated workspace and branch.

![CWT Demo](demo/cwt-config.gif)

## Why CWT?

- **Parallel Development**: Multiple Claude agents working simultaneously on different features
- **No Conflicts**: Each agent has its own directory and git branch via worktrees
- **Coordinated Work**: Agents communicate via messages, coordinator orchestrates merges
- **Budget Control**: Set spending limits and monitor usage in real-time
- **Safe by Default**: Hooks prevent workers from dangerous operations (push, merge, deploy)

## Features

| Feature | Description |
|---------|-------------|
| **Git Worktrees** | Each worker gets isolated directory + branch |
| **Tmux Sessions** | All agents in one terminal, easy navigation |
| **Inter-Agent Messaging** | `wt-msg`, `wt-task` for coordination |
| **MCP Server** | Native Claude tools via Model Context Protocol |
| **Skills** | Workflow templates for coordinator/worker roles |
| **Knowledge Base** | Shared patterns and guidelines (`wt-kb`) |
| **Budget Control** | Spending limits with usage tracking |
| **Bash Validator** | Blocks dangerous commands for workers |
| **Auto-Continue** | Pulser detects idle agents and prompts them |
| **Context Compaction** | Detects and handles context window resets |

## Quick Start

```bash
# 1. Install
git clone https://github.com/marcelomessa/claude-worktrees.git
cd claude-worktrees && ./install.sh

# 2. Setup project
mkdir ~/my-project && cd ~/my-project
git clone https://github.com/your/repo.git main
cwt init --repo main --name my-project

# 3. Create workers
wt-init frontend backend

# 4. Start
cwt
```

Press `Ctrl+B ?` inside tmux to see keyboard shortcuts and budget status.

## How It Works

### Git Worktrees

Traditional git requires switching branches, losing your current state. Worktrees allow multiple checkouts simultaneously:

```
my-project/
├── main/                      ← Coordinator (main branch)
│   └── .git/
├── workspace-frontend/        ← Worker (feature/frontend branch)
│   └── .git → ../main/.git
└── workspace-backend/         ← Worker (feature/backend branch)
    └── .git → ../main/.git
```

Each Claude instance works in its own directory with its own branch. No conflicts, true parallel development.

### Coordinator + Workers

```
┌─────────────────────────────────────────────────────────────────┐
│                      TMUX SESSION                               │
├─────────────────────────────────────────────────────────────────┤
│  Window 0: COORDINATOR (main/)                                  │
│  └── Plans, delegates tasks, merges branches, deploys           │
├─────────────────────────────────────────────────────────────────┤
│  Window 1: WORKER frontend (workspace-frontend/)                │
│  └── Implements frontend features on feature/frontend branch    │
├─────────────────────────────────────────────────────────────────┤
│  Window 2: WORKER backend (workspace-backend/)                  │
│  └── Implements backend features on feature/backend branch      │
└─────────────────────────────────────────────────────────────────┘
```

**Communication flow:**
1. Coordinator sends tasks: `wt-task frontend "Implement login form"`
2. Worker completes and reports: `wt-msg send coordinator "Login done"`
3. Coordinator merges branches and deploys

## Installation

### Requirements

- git 2.5+ (worktree support)
- tmux
- jq
- Node.js (for daemon)
- Claude Code CLI

### Install

```bash
git clone https://github.com/marcelomessa/claude-worktrees.git
cd claude-worktrees
./install.sh
```

Installs to `~/.claude-worktrees/` with symlinks in `~/bin/`.

## Usage

### Project Setup

```bash
# Initialize new project
mkdir ~/projects/my-app && cd ~/projects/my-app
git clone git@github.com:user/repo.git main
cwt init --repo main --name my-app

# Create worker worktrees
wt-init frontend backend api

# Start session
cwt
```

### Session Management

```bash
cwt                     # Start or attach to session
cwt --solo              # Coordinator only (no workers)
cwt -c                  # Continue previous Claude sessions
cwt --strict            # Use Claude's native permissions
cwt --list              # List current project session
cwt --kill              # End session
```

### Tmux Navigation

| Key | Action |
|-----|--------|
| `Ctrl+B 0-9` | Switch to window N |
| `Ctrl+B n/p` | Next/Previous window |
| `Ctrl+B d` | Detach (keeps running) |
| `Ctrl+B ?` | Help & Settings popup |

### Copy & Scroll (macOS)

| Key | Action |
|-----|--------|
| `fn+Opt + Mouse` | Select text, then `Cmd+C` to copy |
| `fn+Opt + Arrows` | Scroll with keyboard |
| Mouse scroll | Also works |

### Inter-Agent Communication

```bash
# Send task
wt-task frontend "Implement user registration"

# Send message
wt-msg send coordinator "Task completed"
wt-msg broadcast "API endpoint changed to /v2"

# Check messages
wt-msg status
wt-msg read
```

### Knowledge Base

```bash
# Search patterns/guidelines
wt-kb query "error handling"
wt-kb list

# Share discovery with team
wt-kb discover "API rate limit is 100/min"
```

### Skills

CWT includes Claude Code skills (workflow templates) that are automatically loaded:

| Skill | Description |
|-------|-------------|
| `cwt-coordinator` | Coordinator role: task distribution, merging, deployment |
| `cwt-worker` | Worker role: boundaries, safe operations, reporting |
| `cwt-kb` | Knowledge base consultation before asking questions |
| `cwt-budget` | Budget awareness before expensive operations |

Skills are installed to `.claude/skills/` in each workspace and teach Claude the CWT workflow.

## Configuration

### Budget Control

Set spending limits per project:

```bash
cwt budget --limit 10 --period daily
cwt budget --limit 50 --period weekly
```

View in help popup (`Ctrl+B ?`) or:

```bash
wt-billing          # Current project cost
wt-billing total    # Total for status bar
```

### MCP Server

CWT includes an MCP (Model Context Protocol) server that provides native Claude tools:

| Tool | Description |
|------|-------------|
| `kb_query` | Search knowledge base |
| `kb_list` | List KB entries |
| `budget_status` | Get current budget/usage |
| `worker_list` | List active workers |
| `send_message` | Send inter-agent message |

The MCP server starts automatically and connects via stdio. Configuration is in `.claude/settings.json`.

### Hooks

CWT uses Claude Code hooks for safety and coordination:

| Hook | Purpose |
|------|---------|
| `bash-validator` | Blocks dangerous commands for workers |
| `file-protector` | Protects sensitive files (.env, Dockerfile) |
| `branch-protector` | Requires work branches, protects main/master |
| `wt-check` | Shows pending messages, detects compaction |

### Session Overrides

Temporarily modify permissions for current session:

```bash
wt-override allow "git push" --duration 2h
wt-override block "rm -rf"
wt-override list
wt-override clear
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CWT_LOG_DIR` | Log directory | `.cwt/logs/` |
| `CWT_PROJECT_ROOT` | Project root | Auto-detected |
| `PULSER_INTERVAL` | Activity check interval | 120s |
| `IDLE_THRESHOLD` | Idle detection threshold | 180s |

## Safety

### Permissionless Mode (Default)

CWT runs Claude with `--dangerously-skip-permissions` to enable autonomous multi-agent operation. Safety is enforced via hooks:

**Workers CANNOT:**
- `git push`, `git merge`, `git rebase`
- `azion deploy`, `npm publish`
- `kill`, `pkill`, `killall`
- Edit `.env`, `Dockerfile`, deploy configs

**Workers CAN:**
- `git add <file>`, `git commit`, `git status`
- `npm run dev/build/test`
- Read files, run tests

### Strict Mode

For environments requiring native Claude permissions:

```bash
cwt --strict
```

## Architecture

### File Structure

```
~/.claude-worktrees/
├── bin/
│   ├── cwt              # Main CLI
│   ├── cwt-help         # Help popup
│   └── tmux-launcher.sh # Session creator
├── lib/
│   ├── wt-msg           # Messaging
│   ├── wt-task          # Task assignment
│   ├── wt-init          # Worktree creation
│   ├── wt-kb            # Knowledge base
│   └── wt-billing       # Cost tracking
├── daemon/
│   ├── index.js         # Main daemon
│   ├── socket-server.js # JSON-RPC over Unix socket
│   └── mcp-server.js    # MCP protocol handler
├── hooks/
│   ├── bash-validator.sh
│   ├── file-protector.sh
│   └── wt-check.sh
└── templates/
    ├── CLAUDE.coord.md  # Coordinator instructions
    └── CLAUDE.worker.md # Worker instructions
```

### Project Structure

```
my-project/
├── .cwt/
│   ├── config.json      # Project config
│   ├── state.json       # Runtime state
│   ├── cwt.sock         # Daemon socket
│   └── logs/
├── main/                # Coordinator repo
├── workspace-frontend/  # Worker worktree
└── workspace-backend/   # Worker worktree
```

### Daemon

The Node.js daemon provides:
- **JSON-RPC** over Unix socket
- **PubSub** messaging between agents
- **MCP Server** for native Claude tools
- **Worker registry** with heartbeats
- **Task queue** for work assignment

## Troubleshooting

### Session already exists

```bash
cwt --kill && cwt
```

### Workers not seeing messages

```bash
# Check daemon
ps aux | grep "daemon/index.js"
ls -la .cwt/cwt.sock

# Restart
cwt --kill && cwt
```

### Worktree not found

```bash
git worktree list
git worktree add ../workspace-name -b feature/name
```

### MCP not connecting

Check `.claude/settings.json` has correct paths:
```json
{
  "mcpServers": {
    "cwt": {
      "command": "node",
      "args": ["~/.claude-worktrees/daemon/mcp-server.js"]
    }
  }
}
```

## Disclaimer

This software orchestrates multiple AI agents that execute commands autonomously
using `--dangerously-skip-permissions` mode. By using this software you acknowledge:

- **Code loss risk**: AI agents may modify, delete, or overwrite files. Safety hooks
  are included but do not guarantee prevention of all destructive actions.
- **No guarantee of correctness**: Code generated or merged by AI agents may contain
  bugs or security vulnerabilities. Review all changes before deploying.
- **Financial risk**: This software makes API calls to Anthropic's Claude service.
  You are responsible for monitoring your own usage and costs.
- **System impact**: Creates tmux sessions, background processes, and executes shell
  commands. Improper use may affect system stability.
- **Data responsibility**: Back up your code before using this software. The authors
  accept no liability for data loss or unintended modifications.

**USE AT YOUR OWN RISK.**

## License

[MIT](LICENSE)
