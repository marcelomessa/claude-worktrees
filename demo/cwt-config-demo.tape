# CWT Configuration Demo - Features & Options
# Run with: vhs cwt-config-demo.tape

Output cwt-config.gif
Set FontSize 14
Set Width 1000
Set Height 600
Set Theme "Dracula"
Set TypingSpeed 5ms
Set Framerate 10

# ============ SETUP ============
Type "# ═══════════════════════════════════════════════════════════"
Enter
Type "# CWT - Claude Worktrees: Configuration & Features"
Enter
Type "# ═══════════════════════════════════════════════════════════"
Enter
Sleep 3s

Type ""
Enter
Type "# 1. SETUP: Clone a repo and initialize CWT"
Enter
Sleep 1s

Type "# Preparing demo environment..."
Enter
Type "cd /tmp && rm -rf cwt-demo && mkdir cwt-demo && cd cwt-demo"
Enter
Sleep 500ms

Hide
Type "cp ~/.claude-worktrees/demo/cwt-demo-help.sh /tmp/cwt-demo/demo-help.sh 2>/dev/null || true"
Enter
Sleep 200ms
Show

Type "git clone https://github.com/expressjs/express.git main --depth 1 -q"
Enter
Sleep 2s

Type ""
Enter
Type "# Initialize CWT project:"
Enter
Type "cwt init --repo main --name my-project"
Enter
Sleep 4s

# ============ WORKTREES (part 1) ============
Ctrl+L
Type "# 2a. WORKTREES: Create isolated workspaces"
Enter
Sleep 1s

Type "wt-init backend frontend 2>&1 | more"
Enter
Sleep 3s
Space
Sleep 3s
Space
Sleep 3s

# ============ WORKTREES (part 2) ============
Ctrl+L
Type "# 2b. WORKTREES: Each has its own directory and branch"
Enter
Sleep 1s

Type "ls -la"
Enter
Sleep 3s

Type "# Each has its own branch:"
Enter
Type "git -C main branch --show-current && git -C workspace-backend branch --show-current"
Enter
Sleep 3s

# ============ PROJECT STRUCTURE ============
Ctrl+L
Type "# 3. PROJECT STRUCTURE"
Enter
Sleep 1s

Type "ls -la .cwt/"
Enter
Sleep 2s

Type "cat .cwt/config.json"
Enter
Sleep 3s

# ============ KNOWLEDGE BASE ============
Ctrl+L
Type "# 4. KNOWLEDGE BASE: Global + Project patterns"
Enter
Sleep 1s

Type "ls ~/.cwt/knowledge/"
Enter
Sleep 2s

Type "wt-kb query 'error handling'"
Enter
Sleep 3s

# ============ SKILLS + MCP ============
Ctrl+L
Type "# 5. SKILLS: Workflow templates for Claude"
Enter
Sleep 1s

Type "ls workspace-backend/.claude/skills/"
Enter
Sleep 2s

Type ""
Enter
Type "# 6. MCP SERVER: Native Claude tools (kb_query, budget_status)"
Enter
Sleep 1s

Type "head -12 workspace-backend/.claude/settings.json"
Enter
Sleep 3s

# ============ BASH VALIDATOR ============
Ctrl+L
Type "# 7. BASH VALIDATOR: Workers cannot git push, merge, rm -rf /"
Enter
Sleep 1s

Type "head -30 ~/.claude-worktrees/hooks/bash-validator.sh | tail -15"
Enter
Sleep 3s

# ============ BUDGET CONTROL ============
Ctrl+L
Type "# 8. BUDGET CONTROL"
Enter
Sleep 1s

Type "cwt budget --limit 5 --period daily"
Enter
Sleep 3s

# ============ RUNNING MODES ============
Ctrl+L
Type "# 9. RUNNING MODES"
Enter
Sleep 1s

Type "# cwt              - All workers (permissionless mode)"
Enter
Sleep 500ms
Type "# cwt --solo       - Coordinator only"
Enter
Sleep 500ms
Type "# cwt -c           - Continue previous session"
Enter
Sleep 500ms
Type "# cwt --strict     - Claude native permissions"
Enter
Sleep 3s

# ============ INTERNAL COMMUNICATION ============
Ctrl+L
Type "# 10. INTERNAL COMMUNICATION (between agents)"
Enter
Type "#     Coordinator delegates tasks, workers report back"
Enter
Sleep 1s

Type "# wt-task worker [task]       - Coordinator sends task"
Enter
Sleep 500ms
Type "# wt-msg send coordinator X   - Worker reports back"
Enter
Sleep 500ms
Type "# wt-msg broadcast [msg]      - Announce to all"
Enter
Sleep 3s

# ============ HELP & SETTINGS (simulated tmux view) ============
Ctrl+L

# Run demo help script that simulates tmux layout
Type "/tmp/cwt-demo/demo-help.sh"
Enter
Sleep 7s
Type "q"
Sleep 1s
