---
title: Git Workflow for Multi-Agent
type: guideline
category: guidelines
keywords: [git, commit, branch, merge, workflow, multi-agent]
---

# Git Workflow for Multi-Agent

## Principles

1. **Workers**: work in their isolated branches
2. **Coordinator**: only one who merges/pushes to main
3. **Communication**: always notify before operations that affect others

## Workflow by Role

### Worker

```bash
# CAN do
git add <specific files>
git commit -m "feat: ..."
git log
git status
git diff

# CANNOT (requires coordinator)
git push                    # blocked
git merge                   # blocked
git rebase                  # blocked
git checkout main/master    # blocked
```

### Coordinator

```bash
# 1. ALWAYS fetch first (updates references)
git fetch origin

# 2. Review worker changes
git diff main..feature/worker-branch

# 3. Ensure you're on main
git checkout main

# 4. Merge with --no-ff (ALWAYS - preserves history)
git merge feature/worker-branch --no-ff -m "Merge feature/X: description"

# 5. Push (after review and tests)
git push origin main
```

### Worktree Merge - Correct Order

1. Worker commits on feature branch (separate worktree)
2. Worker notifies coordinator: `wt-msg send coordinator "done"`
3. Coordinator runs `git fetch origin`
4. Coordinator reviews: `git diff main..feature/branch`
5. Coordinator merges: `git merge feature/branch --no-ff`
6. Coordinator pushes: `git push origin main`
7. Coordinator notifies worker for next task

## Before Commit

1. Check changes: `git diff`
2. Add specific files: `git add file1 file2`
3. Never use: `git add -A` or `git add .`

## Commit Messages

```
<type>(<scope>): <description>

Types: feat, fix, docs, style, refactor, test, chore
Scope: optional, affected area

Examples:
feat(auth): add login with OAuth
fix(api): handle rate limit errors
```

## Safe Recovery

```bash
# View previous version WITHOUT losing current
git show HEAD~1:path/to/file

# Compare with previous version
git diff HEAD~1 -- path/to/file

# Save current work before any risky operation
git stash push -m "backup before risky operation"
```

## NEVER Do

- `git checkout -- .` (loses changes)
- `git reset --hard` (loses everything)
- `git clean -fd` (removes files)
- Push without coordinator review
