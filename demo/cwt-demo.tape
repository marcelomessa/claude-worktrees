# CWT Demo - Multi-Agent Claude Environment
# Run with: vhs cwt-demo.tape

Output demo.gif
Set FontSize 14
Set Width 1400
Set Height 800
Set Theme "Dracula"
Set TypingSpeed 50ms

# Intro
Type "# CWT - Claude Worktrees: Multi-Agent Claude Environment"
Enter
Sleep 1s

# Setup
Type "# Step 1: Setup demo environment"
Enter
Sleep 500ms

Type "cd /tmp && rm -rf cwt-demo && mkdir cwt-demo && cd cwt-demo"
Enter
Sleep 1s

Type "git clone https://github.com/expressjs/express.git main --depth 1 2>/dev/null"
Enter
Sleep 3s

# Init CWT
Type "# Step 2: Initialize CWT project"
Enter
Sleep 500ms

Type "cwt init --repo main --name express-demo"
Enter
Sleep 2s

# Create worker
Type "# Step 3: Create a worker worktree"
Enter
Sleep 500ms

Type "wt-init api-worker"
Enter
Sleep 3s

# Show structure
Type "# Step 4: Project structure"
Enter
Sleep 500ms

Type "ls -la"
Enter
Sleep 1s

Type "cat .cwt/config.json"
Enter
Sleep 2s

# Start CWT (background, no attach)
Type "# Step 5: Start multi-agent environment"
Enter
Sleep 500ms

# Use tmux-launcher directly without attach
Type "SESSION_NAME=cwt-express-demo CWT_PROJECT_ROOT=/tmp/cwt-demo ~/.claude-worktrees/bin/tmux-launcher.sh api-worker &"
Enter
Sleep 8s

Type "# Waiting for Claude to start..."
Enter
Sleep 5s

# Now attach and show
Type "tmux attach -t cwt-express-demo"
Enter
Sleep 3s

# Send task to coordinator (inside tmux)
Type "Analyze the express.js codebase and tell me the main entry point"
Enter
Sleep 15s

# Switch to worker window
Ctrl+b
Type "1"
Sleep 5s

# Back to coordinator
Ctrl+b
Type "0"
Sleep 3s

# Check messages
Type "wt-msg status"
Enter
Sleep 3s

# Detach
Ctrl+b
Type "d"
Sleep 1s

# Cleanup
Type "# Demo complete! Cleaning up..."
Enter
Type "tmux kill-session -t cwt-express-demo 2>/dev/null"
Enter
Sleep 1s

Type "# CWT enables multiple Claude agents working together!"
Enter
Sleep 2s
