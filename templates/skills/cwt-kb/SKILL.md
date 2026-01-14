---
name: cwt-kb
description: Knowledge Base consultation. Use BEFORE asking questions to check if answers already exist, when unsure about patterns or guidelines, or when looking for project conventions.
allowed-tools: mcp__cwt__kb_query, mcp__cwt__kb_list, mcp__cwt__kb_get
---

# Knowledge Base Consultation

## When to Use

- Before asking the coordinator a question
- When unsure about coding patterns
- When looking for project conventions
- When you need architectural decisions

## How to Use

**Search for answers:**
```
kb_query "error handling"
kb_query "git workflow"
kb_query "testing"
```

**Browse categories:**
```
kb_list                    # All entries
kb_list category=patterns  # Just patterns
kb_list category=guidelines
```

**Get full content:**
```
kb_get "error-handling"
kb_get "patterns-error-handling"
```

## Categories

- **patterns** - Reusable code patterns
- **guidelines** - Development workflows
- **architecture** - Project decisions

## If No Answer Found

Only then escalate to coordinator:
```bash
wt-msg send coordinator "Question: [your question]. Checked KB, no answer found."
```
