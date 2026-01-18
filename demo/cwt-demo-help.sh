#!/bin/bash
# =============================================================================
# CWT Demo Help - Simulates tmux display with help popup for demo GIF
# =============================================================================

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BG_GRAY='\033[48;5;238m'
BG_GREEN='\033[48;5;34m'
RESET='\033[0m'

# Get terminal size
COLS=$(tput cols)
ROWS=$(tput lines)

clear

# Draw main content area (simulated Claude output)
echo ""
echo -e "${WHITE}  Claude is working...${RESET}"
echo ""
echo "  > Analyzing codebase structure..."
echo "  > Found 12 TypeScript files"
echo "  > Checking dependencies..."
echo ""
echo ""

# Draw the help popup (centered-ish)
cat << 'HELP'
  ╔═══════════════════════════════════════════════════════════════════╗
  ║                    CWT - Claude Worktrees                         ║
  ║                    Settings & Help                                ║
  ╚═══════════════════════════════════════════════════════════════════╝

    BUDGET STATUS
    ─────────────────────────────────────────────────────────────────
      Limit:   $5.00 (daily)
      Usage:   $2.35
      [███████░░░░░░░░░░░░░░░░░░░░░░░] 47%

    TMUX NAVIGATION
    ─────────────────────────────────────────────────────────────────
      Ctrl+B 0-9        Switch to window N (0=coord, 1+=workers)
      Ctrl+B n/p        Next/Previous window
      Ctrl+B d          Detach (session keeps running)
      Ctrl+B ?          Show this help

    COPY & SCROLL (macOS)
    ─────────────────────────────────────────────────────────────────
      fn+Opt + Mouse    Select text, then Cmd+C to copy
      fn+Opt + Arrows   Scroll with keyboard
      Mouse scroll      Also works (mouse mode enabled)

    AGENT COMMANDS
    ─────────────────────────────────────────────────────────────────
      wt-task <worker> "task"    Send task to worker
      wt-msg send <to> "msg"     Send message
      wt-kb query "text"         Search knowledge base

    ─────────────────────────────────────────────────────────────────
      [b] Configure budget    [r] Refresh    [q] Close

HELP

echo ""

# Draw the tmux status bar at the bottom
# First, move cursor down to leave space
for i in $(seq 1 3); do echo ""; done

# Status bar
TIME=$(date +%H:%M)
BUDGET="\$2.35/\$5"

# Build status line
printf "${BG_GRAY}${GREEN}[cwt-demo] ${RESET}"
printf "${BG_GREEN}${WHITE} 0:coordinator ${RESET}"
printf "${BG_GRAY}${WHITE} 1:backend ${RESET}"
printf "${BG_GRAY}${WHITE} 2:frontend ${RESET}"

# Calculate padding for right side
LEFT_LEN=50
RIGHT_CONTENT="${BUDGET} ${TIME}"
RIGHT_LEN=${#RIGHT_CONTENT}
PADDING=$((COLS - LEFT_LEN - RIGHT_LEN - 2))

printf "%${PADDING}s" ""
printf "${BG_GRAY}${CYAN}${BUDGET}${RESET}"
printf "${BG_GRAY} ${YELLOW}${TIME}${RESET}"
printf "${BG_GRAY}%$((COLS - LEFT_LEN - PADDING - RIGHT_LEN - 2))s${RESET}\n"

# Wait for input
read -n 1 -s
