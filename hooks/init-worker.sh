#!/bin/bash
# =============================================================================
# INIT-WORKER - Hook executed when Claude session starts
# =============================================================================
# Registers worker, checks for pending tasks and messages
# =============================================================================

WORKER_ID="${CLAUDE_WORKER_ID:-$(basename "$PWD")}"
STATE_FILE="/tmp/claude-wt-state.json"
TASKS_DIR="/tmp/claude-wt-tasks"

# Initialize state if needed
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"workers":{},"messages":[],"tasks":{}}' > "$STATE_FILE"
fi

# Register worker
jq ".workers[\"$WORKER_ID\"] = {\"status\":\"active\",\"started\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true

echo "======================================="
echo " WORKER: $WORKER_ID"
echo "======================================="

# Check for pending task
TASK_FILE="$TASKS_DIR/${WORKER_ID}.task"
if [[ -f "$TASK_FILE" ]]; then
  echo ""
  echo ">>> PENDING TASK <<<"
  cat "$TASK_FILE"
  echo ""
  echo "======================================="
fi

# Check for pending messages
msg_count=$(jq "[.messages[] | select(.to == \"$WORKER_ID\" or .to == \"all\") | select(.read == false)] | length" "$STATE_FILE" 2>/dev/null || echo 0)
if [[ "$msg_count" -gt 0 ]]; then
  echo ""
  echo "$msg_count message(s) pending"
  echo "Run: wt-msg read"
fi
