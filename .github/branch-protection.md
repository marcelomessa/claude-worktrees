# Branch Protection Setup

Configure in GitHub > Settings > Branches > Branch protection rules:

## Rule: `main`

- [x] Require a pull request before merging
  - [x] Require approvals: 1
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [x] Require review from Code Owners
- [x] Require status checks to pass before merging
  - Required checks: `ShellCheck`, `Bash Syntax Check`, `Security Scan`
- [x] Require branches to be up to date before merging
- [x] Do not allow bypassing the above settings
- [ ] Require signed commits (optional)
- [x] Restrict who can push to matching branches
  - Only maintainers

## Setup via CLI

```bash
gh api repos/marcelomessa/claude-worktrees/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["ShellCheck","Bash Syntax Check","Security Scan"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":true}' \
  --field restrictions=null
```
