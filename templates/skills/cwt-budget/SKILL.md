---
name: cwt-budget
description: Budget management and cost awareness. Use before starting large tasks, refactors, or expensive operations to ensure sufficient budget.
allowed-tools: mcp__cwt__budget_status, mcp__cwt__budget_check
---

# Budget Management

## When to Check Budget

- Before starting large implementations
- Before refactoring multiple files
- Before exploratory tasks with unclear scope
- When planning work for the session

## How to Use

**Check current status:**
```
budget_status
```

Returns: limit, current spend, remaining, status (ok/warning/exceeded)

**Check if task fits budget:**
```
budget_check estimated_cost=5.0 task_description="Refactor auth module"
```

Returns: can_proceed, recommendation

## If Budget Low

1. **Simplify** - Do minimum viable version
2. **Prioritize** - Focus on critical parts only
3. **Ask** - Request budget increase from user
4. **Defer** - Postpone non-essential work

## Cost Estimates (rough)

- Simple file edit: $0.10-0.50
- New feature (small): $1-3
- Refactor (medium): $3-10
- Large implementation: $10+

These vary based on complexity and iterations.

## Budget Status Meanings

- **ok** - Proceed normally
- **warning** - Be efficient, avoid unnecessary exploration
- **exceeded** - Stop, ask user before continuing
