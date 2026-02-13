#!/bin/bash
# =============================================================================
# WT-CHECK - Coordination status for CWT
# =============================================================================
# Used by Claude hooks to show communication status
#
# Usage:
#   wt-check.sh status    # Full status (UserPromptSubmit)
#   wt-check.sh quick     # Quick check (PostToolUse)
# =============================================================================

MODE="${1:-status}"
WORKER_ID="${CLAUDE_WORKER_ID:-$(basename "$PWD")}"

# Find project socket
find_socket() {
  # 1. Environment variable
  if [[ -n "$CWT_SOCKET" && -S "$CWT_SOCKET" ]]; then
    echo "$CWT_SOCKET"
    return 0
  fi

  # 2. Walk up tree looking for .cwt/cwt.sock
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -S "$dir/.cwt/cwt.sock" ]]; then
      echo "$dir/.cwt/cwt.sock"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  return 1
}

SOCKET=$(find_socket)

# If no socket, exit silently
[[ -z "$SOCKET" || ! -S "$SOCKET" ]] && exit 0

# Function to send request to daemon
send_request() {
  echo "$1" | nc -w 1 -U "$SOCKET" 2>/dev/null
}

# Register worker and send request
send_as_worker() {
  local request="$1"
  (
    echo "{\"method\":\"register\",\"params\":{\"id\":\"$WORKER_ID\"},\"id\":0}"
    sleep 0.1
    echo "$request"
  ) | nc -w 2 -U "$SOCKET" 2>/dev/null | tail -1
}

# Check if daemon is responding
check_daemon() {
  local pong=$(echo '{"method":"ping","id":1}' | nc -w 1 -U "$SOCKET" 2>/dev/null)
  if echo "$pong" | grep -q "pong"; then
    return 0
  fi
  return 1
}

# =============================================================================
# STATUS MODE - Minimal output (UserPromptSubmit)
# =============================================================================
mode_status() {
  # Check for compaction marker (created by PreCompact hook)
  local cwt_root=""
  if [[ -n "$CWT_PROJECT_ROOT" && -d "$CWT_PROJECT_ROOT/.cwt" ]]; then
    cwt_root="$CWT_PROJECT_ROOT"
  else
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
      if [[ -d "$dir/.cwt" ]]; then
        cwt_root="$dir"
        break
      fi
      dir=$(dirname "$dir")
    done
  fi

  if [[ -n "$cwt_root" && -f "$cwt_root/.cwt/compacted.marker" ]]; then
    rm -f "$cwt_root/.cwt/compacted.marker"
    echo "CONTEXT COMPACTED - STOP and report to coordinator:"
    echo "wt-msg send coordinator \"CONTEXT RESET - Done: [X] | Doing: [Y] | Plan: [Z] | Decisions: [W]\""
    echo ""
  fi

  if ! check_daemon; then
    return
  fi

  # Register heartbeat
  send_as_worker '{"method":"heartbeat","id":1}' >/dev/null

  # Get unread messages
  local messages=$(send_as_worker '{"method":"get_messages","id":2}')
  local msg_count=$(echo "$messages" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msgs = [m for m in data.get('result', []) if not m.get('read', False)]
    print(len(msgs))
except:
    print(0)
" 2>/dev/null || echo 0)

  # Check active votes
  local votes=$(send_request '{"method":"get_active_votes","id":3}')
  local vote_count=$(echo "$votes" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('result', [])))
except:
    print(0)
" 2>/dev/null || echo 0)

  # Only output if something pending
  local output=""
  [[ "$msg_count" -gt 0 ]] && output="$msg_count msgs"
  [[ "$vote_count" -gt 0 ]] && {
    [[ -n "$output" ]] && output="$output, "
    output="${output}$vote_count vote(s)"
  }

  [[ -n "$output" ]] && echo "CWT: $output"
}

# =============================================================================
# QUICK MODE - Minimal check (PostToolUse)
# =============================================================================
mode_quick() {
  if ! check_daemon; then
    return
  fi

  # Register heartbeat
  send_as_worker '{"method":"heartbeat","id":1}' >/dev/null

  # Check messages
  local messages=$(send_as_worker '{"method":"get_messages","id":2}')
  local msg_count=$(echo "$messages" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msgs = [m for m in data.get('result', []) if not m.get('read', False)]
    print(len(msgs))
except:
    print(0)
" 2>/dev/null || echo 0)

  # Check votes
  local votes=$(send_request '{"method":"get_active_votes","id":3}')
  local vote_count=$(echo "$votes" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('result', [])))
except:
    print(0)
" 2>/dev/null || echo 0)

  # Only output if something pending
  local output=""
  [[ "$msg_count" -gt 0 ]] && output="$msg_count msgs"
  [[ "$vote_count" -gt 0 ]] && {
    [[ -n "$output" ]] && output="$output, "
    output="${output}$vote_count vote(s)"
  }

  [[ -n "$output" ]] && echo "CWT: $output"
}

# =============================================================================
# MAIN
# =============================================================================
case "$MODE" in
  status)
    mode_status
    ;;
  quick)
    mode_quick
    ;;
  *)
    echo "Usage: wt-check.sh [status|quick]"
    exit 1
    ;;
esac

exit 0
