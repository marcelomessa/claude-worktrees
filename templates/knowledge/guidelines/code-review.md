---
title: Code Review Guidelines
type: guideline
category: guidelines
keywords: [review, code, quality, standards, pr, pull-request]
---

# Code Review Guidelines

## Before Requesting Review

1. Code compiles/runs without errors
2. Tests pass (if they exist)
3. Clear commit message
4. Focused changes (one feature/fix at a time)

## Review Checklist

### Functionality
- [ ] Solves the proposed problem
- [ ] Doesn't break existing features
- [ ] Edge cases handled

### Security
- [ ] Input validation (especially user input)
- [ ] No hardcoded secrets
- [ ] No SQL injection / XSS vulnerabilities
- [ ] Permissions verified

### Quality
- [ ] Readable and self-documented code
- [ ] No unnecessary duplication
- [ ] No dead / commented-out code
- [ ] Meaningful names (variables, functions)

### Performance
- [ ] No N+1 queries
- [ ] No unnecessary loops
- [ ] Resources released (files, connections)

## Communication Worker → Coordinator

```bash
# Notify that it's ready for review
wt-msg send coordinator "Branch frontend-auth ready for review"

# Details of what was done
wt-msg send coordinator "Implemented OAuth login. See commits in frontend-auth"
```

## Communication Coordinator → Worker

```bash
# Approve
wt-msg send frontend "Approved! Will merge now"

# Request changes
wt-msg send frontend "Please: 1) Add email validation, 2) Handle error 401"
```

## Merge Checklist

- [ ] CI passed (if available)
- [ ] Conflicts resolved
- [ ] Changelog updated (if applicable)
- [ ] Branch can be deleted after merge
