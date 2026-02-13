---
title: Multi-Agent Communication
type: pattern
category: patterns
keywords: [multi-agent, communication, coordinator, worker, message, broadcast]
---

# Multi-Agent Communication

## Hierarchy

```
coordinator (central)
    ├── worker-1 (frontend)
    ├── worker-2 (backend)
    └── worker-3 (docs)
```

## When to Communicate

### Worker → Coordinator

1. **Blocker**: cannot proceed
2. **Architectural decision**: affects other workers
3. **Review needed**: code ready for merge
4. **Important discovery**: useful info for others

```bash
wt-msg send coordinator "BLOCKER: API /users returns 404, need the endpoint"
wt-msg send coordinator "DECISION: use Redux or Context for state?"
wt-msg send coordinator "REVIEW: branch feature-x ready"
```

### Coordinator → Worker

1. **Task assignment**: new task
2. **Blocker response**: solution/guidance
3. **Broadcast**: general info

```bash
wt-task backend "Implement endpoint /api/users"
wt-msg send frontend "API is ready: POST /api/auth/login"
wt-msg broadcast "Architecture change: everyone use TypeScript strict"
```

### Worker → Worker

Generally via discoveries (avoid direct communication):

```bash
wt-kb discover "API rate limit" "API /search has limit 100/min"
```

## Message Format

### Blocker
```
BLOCKER: [short description]
Context: [what you tried]
Need: [what you need]
```

### Discovery
```
DISCOVERY: [title]
[description]
Relevance: [who should know]
```

### Task Completion
```
DONE: [task]
Files: [list of modified files]
Branch: [branch name]
```

## Anti-patterns

- Messages too long (summarize)
- Asking without researching first (`wt-kb query`)
- Direct worker-worker communication for decisions (use coordinator)
- Not reporting blockers (being stuck silently)
