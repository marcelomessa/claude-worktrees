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

COLS=$(tput cols)

clear

# Draw the help popup
cat << 'HELP'
  ╔═══════════════════════════════════════════════════════════════════╗
  ║                    CWT - Claude Worktrees                         ║
  ║                    Settings & Help     (Ctrl+B ?)                 ║
  ╚═══════════════════════════════════════════════════════════════════╝

    BUDGET STATUS
    ─────────────────────────────────────────────────────────────────
      Limit:   $5.00 (daily)        Usage:   $2.35
      [███████░░░░░░░░░░░░░░░░░░░░░░░] 47%

    TMUX NAVIGATION
    ─────────────────────────────────────────────────────────────────
      Ctrl+B 0-9        Switch window (0=coord, 1+=workers)
      Ctrl+B n/p        Next/Previous window
      Ctrl+B d          Detach (keeps running)

    COPY & SCROLL (macOS)
    ─────────────────────────────────────────────────────────────────
      fn+Opt + Mouse    Select text, then Cmd+C to copy
      fn+Opt + Arrows   Scroll with keyboard

    AGENT COMMANDS
    ─────────────────────────────────────────────────────────────────
      wt-task <worker> "task"    Send task to worker
      wt-msg send <to> "msg"     Send message
      wt-kb query "text"         Search knowledge base

    ─────────────────────────────────────────────────────────────────
      [b] Configure budget    [r] Refresh    [q] Close
HELP

echo ""

# Draw the tmux status bar
TIME=$(date +%H:%M)
BUDGET="\$2.35/\$5"

printf "${BG_GRAY}${GREEN}[cwt-demo] ${RESET}"
printf "${BG_GREEN}${WHITE} 0:coordinator ${RESET}"
printf "${BG_GRAY}${WHITE} 1:backend ${RESET}"
printf "${BG_GRAY}${WHITE} 2:frontend ${RESET}"

LEFT_LEN=50
RIGHT_CONTENT="${BUDGET} ${TIME}"
RIGHT_LEN=${#RIGHT_CONTENT}
PADDING=$((COLS - LEFT_LEN - RIGHT_LEN - 2))

printf "%${PADDING}s" ""
printf "${BG_GRAY}${CYAN}${BUDGET}${RESET}"
printf "${BG_GRAY} ${YELLOW}${TIME}${RESET}"
printf "${BG_GRAY}%$((COLS - LEFT_LEN - PADDING - RIGHT_LEN - 2))s${RESET}\n"

read -n 1 -s
