# Demo Script - CWT (Claude Worktrees)

**Estimated duration:** 5-7 minutes

---

## Preparation (before recording)

```bash
# Clean previous environment
cd /tmp && rm -rf cwt-demo
tmux kill-session -t cwt-my-project 2>/dev/null

# Have a repo to clone (e.g.: expressjs/express or your own)
```

---

## PART 1: Initial Setup (1 min)

### 1.1 Create project

```bash
cd /tmp
mkdir cwt-demo && cd cwt-demo

# Clone an example repo
git clone https://github.com/expressjs/express.git main --depth 1

# Initialize CWT
cwt init --repo main --name my-project
```

**Narration:** "CWT creates a project structure with isolated configuration in .cwt/"

### 1.2 Show structure

```bash
ls -la
cat .cwt/config.json
```

---

## PART 2: Create Workers (1 min)

### 2.1 Create worktrees

```bash
wt-init backend frontend
```

**Narration:** "Each worker gets its own isolated directory and branch"

### 2.2 Show result

```bash
ls -la
git -C main worktree list
```

---

## PART 3: Start Multi-Agent Session (1 min)

### 3.1 Start CWT

```bash
cwt
```

**Narration:** "CWT starts a tmux session with coordinator and workers in separate windows"

### 3.2 Navigate between windows

- `Ctrl+B 0` - Coordinator
- `Ctrl+B 1` - Backend worker
- `Ctrl+B 2` - Frontend worker

**Narration:** "Each Claude agent works independently in its workspace"

---

## PART 4: Communication Between Agents (1 min)

### 4.1 Send task (from coordinator)

```bash
wt-task backend "Create endpoint GET /api/users"
wt-task frontend "Create UserList component"
```

### 4.2 View message status

```bash
wt-msg status
```

### 4.3 Worker responds (switch to worker window)

```bash
# Ctrl+B 1 (go to backend)
wt-msg read
wt-msg send coordinator "Endpoint created in routes/users.js"
```

---

## PART 5: Knowledge Base (30s)

### 5.1 Query patterns

```bash
wt-kb query "error handling"
wt-kb list
```

**Narration:** "Workers consult the knowledge base before asking the coordinator"

---

## PART 6: Budget Control (30s)

### 6.1 Configure limit

```bash
cwt budget --limit 10 --period daily
```

### 6.2 View status

```bash
wt-billing
```

**Narration:** "Per-project cost control with configurable limits"

---

## PART 7: Help & Settings (30s)

### 7.1 Open help popup

- Press `Ctrl+B ?`

**Narration:** "The popup shows shortcuts, budget status and allows configuration"

- Press `q` to close

---

## PART 8: Security (30s)

### 8.1 Show that worker cannot push

```bash
# In the worker window
git push
# Will be blocked by bash-validator
```

**Narration:** "Workers are prevented from destructive operations - only the coordinator can push, merge and deploy"

---

## PART 9: Wrap Up (15s)

### 9.1 Detach from session

- `Ctrl+B d`

**Narration:** "The session continues running in the background"

### 9.2 Show that session exists

```bash
cwt --list
```

### 9.3 Reconnect

```bash
cwt
```

### 9.4 Terminate

```bash
cwt --kill
```

---

## Key Points to Emphasize

1. **Isolation** - Each worker has its own directory and branch
2. **Coordination** - Structured communication via messages
3. **Security** - Hooks prevent dangerous operations
4. **Budget** - Real-time cost control
5. **Knowledge Base** - Shared patterns between agents
6. **Skills** - Claude already knows its role (coordinator/worker)

---

## Quick Reference Commands

| Command | Description |
|---------|-------------|
| `cwt init --repo X --name Y` | Initialize project |
| `wt-init worker1 worker2` | Create worktrees |
| `cwt` | Start/reconnect session |
| `cwt --solo` | Coordinator only |
| `cwt --kill` | Terminate session |
| `wt-task worker "msg"` | Send task |
| `wt-msg send to "msg"` | Send message |
| `wt-msg status` | View messages |
| `wt-kb query "X"` | Search KB |
| `cwt budget --limit X` | Set limit |
| `Ctrl+B ?` | Help popup |
| `Ctrl+B 0-9` | Switch window |
| `Ctrl+B d` | Detach |
