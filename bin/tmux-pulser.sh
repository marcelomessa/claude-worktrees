#!/bin/bash
# =============================================================================
# TMUX PULSER - Monitors Claude workers and sends commands when idle
# =============================================================================
# Tmux version of the original pulser
# =============================================================================

# Detect .cwt/ by walking up the directory tree
find_cwt_root() {
  # 1. Environment variable
  if [[ -n "$CWT_PROJECT_ROOT" && -d "$CWT_PROJECT_ROOT/.cwt" ]]; then
    echo "$CWT_PROJECT_ROOT"
    return 0
  fi

  # 2. Walk up tree
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.cwt" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  return 1
}

# Determine state files
CWT_ROOT=$(find_cwt_root)
if [[ -n "$CWT_ROOT" ]]; then
  PROJECT_NAME=$(basename "$CWT_ROOT")
  SESSION_NAME="${SESSION_NAME:-cwt-$PROJECT_NAME}"
  STATE_FILE="$CWT_ROOT/.cwt/state.json"
  WORKSPACES_FILE="$CWT_ROOT/.cwt/workers.txt"
  LOG_FILE="$CWT_ROOT/.cwt/cwt-pulser.log"
else
  SESSION_NAME="${SESSION_NAME:-cwt}"
  STATE_FILE="/tmp/claude-wt-state.json"
  WORKSPACES_FILE="/tmp/cwt-workers-list.txt"
  LOG_FILE="/tmp/cwt-pulser.log"
fi

# Token optimization: longer intervals to reduce unnecessary checks
INTERVAL="${PULSER_INTERVAL:-120}"        # Check every 2 minutes (was 30s)
IDLE_THRESHOLD="${IDLE_THRESHOLD:-180}"   # Worker idle threshold: 3 minutes (was 60s)
BILLING_INTERVAL="${BILLING_INTERVAL:-300}" # Update billing every 5 minutes
BILLING_CACHE="$HOME/.cwt-billing-cache"
LAST_BILLING_UPDATE=0

# Resolve script directory for wt-billing
SCRIPT_PATH="$0"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
  SCRIPT_PATH=$(readlink "$SCRIPT_PATH")
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
CWT_BIN_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
WT_BILLING="$CWT_BIN_DIR/../lib/wt-billing"

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

update_billing_cache() {
  local now=$(date +%s)
  local elapsed=$((now - LAST_BILLING_UPDATE))

  if [[ $elapsed -ge $BILLING_INTERVAL ]]; then
    if [[ -x "$WT_BILLING" ]]; then
      "$WT_BILLING" total > "$BILLING_CACHE" 2>/dev/null &
      LAST_BILLING_UPDATE=$now
      log "💰 Billing cache updated"
    fi
  fi
}

> "$LOG_FILE"
log "🔄 Tmux Pulser started"
log "   Session: $SESSION_NAME"
log "   Interval: ${INTERVAL}s"
log "   Billing interval: ${BILLING_INTERVAL}s"

extract_datetime() {
  local content="$1"
  echo "$content" | grep -oE '\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]' | tail -1 | tr -d '[]'
}

seconds_since() {
  local time_str="$1"
  [[ -z "$time_str" ]] && echo "999999" && return

  local now=$(date '+%H:%M:%S')
  local now_sec=$(date -j -f '%H:%M:%S' "$now" '+%s' 2>/dev/null)
  local then_sec=$(date -j -f '%H:%M:%S' "$time_str" '+%s' 2>/dev/null)

  [[ -z "$now_sec" || -z "$then_sec" ]] && echo "999999" && return

  local diff=$((now_sec - then_sec))
  [[ $diff -lt 0 ]] && diff=$((diff + 86400))
  echo "$diff"
}

has_pending_messages() {
  local worker_id="$1"
  if [[ -f "$STATE_FILE" ]]; then
    local count=$(jq -r ".workers[\"$worker_id\"].messages | length // 0" "$STATE_FILE" 2>/dev/null)
    [[ "$count" -gt 0 && "$count" != "null" ]] && return 0
  fi
  return 1
}

check_window() {
  local window_num="$1"
  local window_name="$2"

  # Capture content via tmux
  local content=$(tmux capture-pane -t "$SESSION_NAME:$window_num" -p 2>/dev/null)
  [[ -z "$content" ]] && return 1

  local last_time=$(extract_datetime "$content")
  local idle_secs=$(seconds_since "$last_time")

  # Detect if Claude is waiting for input
  # Indicators: "bypass permissions" or empty line after separator ────
  local waiting_input=false
  if echo "$content" | tail -3 | grep -qE 'bypass permissions|shift\+tab to cycle' 2>/dev/null; then
    waiting_input=true
  fi

  # Detect if there's text in the input buffer (text before ↵ send)
  local has_pending_input=false
  if echo "$content" | tail -5 | grep -qE '↵ send' 2>/dev/null; then
    has_pending_input=true
  fi

  # Detect if Claude is processing
  # Indicators: spinner, "Thinking", "Hatching", "Investigating", time counter
  local is_busy=false
  if echo "$content" | tail -10 | grep -qE '⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|✻|Thinking|Working|Hatching|Investigating|Reading|Searching|Analyzing|[0-9]+m [0-9]+s|[0-9]+s \·' 2>/dev/null; then
    is_busy=true
    waiting_input=false
  fi

  # Detect if there are queued messages (indicator that something is already pending)
  if echo "$content" | tail -5 | grep -qE 'Press up to edit queued|queued messages' 2>/dev/null; then
    is_busy=true
    waiting_input=false
  fi

  local has_msgs=false
  has_pending_messages "$window_name" && has_msgs=true

  log "   [$window_num] $window_name: idle=${idle_secs}s waiting=$waiting_input busy=$is_busy pending=$has_pending_input"

  # If there's pending input (typed text waiting for Enter)
  # TODO: Detect if it's Claude's auto-suggestion (has dim/italic ANSI codes)
  # For now: workers execute after threshold, coordinator never
  if [[ "$has_pending_input" == "true" ]]; then
    if [[ "$window_name" == "coordinator" ]]; then
      # Coordinator: never auto-submit pending input (could be auto-suggestion)
      log "   ⏸️  Pending input in coordinator - waiting for human"
      return 1
    elif [[ $idle_secs -gt $IDLE_THRESHOLD ]]; then
      # Worker: submit after threshold (probably a command from coordinator)
      log "   ➡️  Sending Enter to $window_name (pending input + idle)"
      tmux send-keys -t "$SESSION_NAME:$window_num" "" C-m
      return 0
    else
      log "   ⏳  Pending input in $window_name - waiting for threshold"
      return 1
    fi
  fi

  # Different threshold for coordinator (human-operated) vs workers (autonomous)
  local threshold=$IDLE_THRESHOLD
  if [[ "$window_name" == "coordinator" ]]; then
    # Coordinator: only intervene after 5 minutes of inactivity, and ONLY if there are messages
    threshold="${COORD_IDLE_THRESHOLD:-300}"
  fi

  # If waiting for input and idle for too long
  if [[ "$waiting_input" == "true" && $idle_secs -gt $threshold ]]; then
    local cmd=""

    if [[ "$window_name" == "coordinator" ]]; then
      # Coordinator: ONLY notify if there are pending messages from workers
      if [[ "$has_msgs" == "true" ]]; then
        cmd="wt-msg read"
      fi
      # DO NOT send "continue" to coordinator - let human decide
    else
      # Worker: only notify if there are pending messages
      # Don't send wt-msg check - it wastes tokens when nothing pending
      if [[ "$has_msgs" == "true" ]]; then
        cmd="wt-msg read"
      fi
      # If no messages, do nothing - let workers communicate naturally
    fi

    if [[ -n "$cmd" ]]; then
      log "   ➡️  Sending '$cmd' to $window_name"
      tmux send-keys -t "$SESSION_NAME:$window_num" "$cmd"
      sleep 0.1
      tmux send-keys -t "$SESSION_NAME:$window_num" "" C-m
      return 0
    fi
  fi

  return 1
}

# Main loop
while true; do
  # Check if tmux session exists
  if ! tmux has-session -t "=$SESSION_NAME" 2>/dev/null; then
    log "❌ Session '$SESSION_NAME' not found. Exiting."
    exit 1
  fi

  # Check if project directory still exists (prevents orphan pulser)
  if [[ -n "$CWT_ROOT" && ! -d "$CWT_ROOT/.cwt" ]]; then
    log "❌ Project '$CWT_ROOT' no longer exists. Stopping orphan pulser."
    exit 1
  fi

  # Update billing cache periodically
  update_billing_cache

  log "🔍 Checking agents..."

  # Check coordinator (window 0)
  check_window 0 "coordinator"

  # Check workers
  if [[ -f "$WORKSPACES_FILE" ]]; then
    window_num=1
    while IFS= read -r worker; do
      [[ -n "$worker" ]] && check_window "$window_num" "$worker"
      ((window_num++))
    done < "$WORKSPACES_FILE"
  else
    log "⚠️  Workspaces file not found"
    for i in {1..3}; do
      check_window "$i" "worker-$i" 2>/dev/null
    done
  fi

  log "💤 Waiting ${INTERVAL}s..."
  sleep "$INTERVAL"
done
