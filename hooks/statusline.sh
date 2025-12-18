#!/bin/bash
# =============================================================================
# STATUSLINE - Custom status line for Claude Code
# =============================================================================
# Shows: [HH:MM:SS] worker-id | directory
# Used by pulser to detect idle workers
# =============================================================================

input=$(cat)
DATETIME=$(date '+%H:%M:%S')
WORKER_ID="${CLAUDE_WORKER_ID:-local}"
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "?"' 2>/dev/null | xargs basename)

echo "[$DATETIME] $WORKER_ID | $DIR"
