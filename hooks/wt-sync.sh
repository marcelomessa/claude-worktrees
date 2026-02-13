#!/bin/bash
# =============================================================================
# WT-SYNC - State synchronization and communication for CWT
# =============================================================================
# Commands for inter-worker communication via daemon
#
# Usage:
#   wt-sync.sh broadcast "message"            # Send to all
#   wt-sync.sh send <worker> "message"        # Send to specific worker
#   wt-sync.sh task-started <task-id>         # Mark task as started
#   wt-sync.sh task-progress <id> "update"    # Update progress
#   wt-sync.sh task-completed <id> "summary"  # Mark as complete
#   wt-sync.sh finding <severity> "desc"      # Report finding
#   wt-sync.sh blocker "description"          # Report blocker
#   wt-sync.sh vote-create "decision" "op1,op2"# Create vote
#   wt-sync.sh vote-cast <id> "option"        # Cast vote
#   wt-sync.sh workers                        # List active workers
# =============================================================================

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

if [[ -z "$SOCKET" || ! -S "$SOCKET" ]]; then
  echo "❌ Daemon not found. Make sure cwt is running."
  exit 1
fi

# Send request to daemon
send_request() {
  echo "$1" | nc -w 2 -U "$SOCKET" 2>/dev/null
}

# Register and send
send_as_worker() {
  local request="$1"
  (
    echo "{\"method\":\"register\",\"params\":{\"id\":\"$WORKER_ID\"},\"id\":0}"
    sleep 0.1
    echo "$request"
  ) | nc -w 2 -U "$SOCKET" 2>/dev/null | tail -1
}

ACTION="$1"
shift

case "$ACTION" in
  # === Communication ===
  broadcast)
    MESSAGE="$1"
    RESPONSE=$(send_as_worker "{\"method\":\"broadcast\",\"params\":{\"data\":{\"message\":\"$MESSAGE\",\"from\":\"$WORKER_ID\"}},\"id\":1}")
    echo "📢 Broadcast sent: $MESSAGE"
    ;;

  send)
    TO="$1"
    MESSAGE="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"send_message\",\"params\":{\"to\":\"$TO\",\"content\":\"$MESSAGE\",\"type\":\"direct\"},\"id\":1}")
    echo "📨 Message sent to $TO"
    ;;

  # === Tasks ===
  task-started)
    TASK_ID="$1"
    RESPONSE=$(send_as_worker "{\"method\":\"update_task\",\"params\":{\"taskId\":\"$TASK_ID\",\"updates\":{\"status\":\"in_progress\",\"assignedTo\":\"$WORKER_ID\"}},\"id\":1}")
    echo "▶️  Task $TASK_ID started"
    ;;

  task-progress)
    TASK_ID="$1"
    PROGRESS="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"update_task\",\"params\":{\"taskId\":\"$TASK_ID\",\"updates\":{\"progress\":\"$PROGRESS\"}},\"id\":1}")
    echo "📝 Task $TASK_ID updated"
    ;;

  task-completed)
    TASK_ID="$1"
    SUMMARY="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"complete_task\",\"params\":{\"taskId\":\"$TASK_ID\",\"summary\":\"$SUMMARY\"},\"id\":1}")
    echo "✅ Task $TASK_ID completed"
    ;;

  # === Findings & Blockers ===
  finding)
    SEVERITY="$1"
    DESCRIPTION="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"add_finding\",\"params\":{\"severity\":\"$SEVERITY\",\"description\":\"$DESCRIPTION\",\"reporter\":\"$WORKER_ID\"},\"id\":1}")
    echo "🔍 Finding reported [$SEVERITY]: $DESCRIPTION"
    ;;

  blocker)
    DESCRIPTION="$1"
    RESPONSE=$(send_as_worker "{\"method\":\"add_blocker\",\"params\":{\"description\":\"$DESCRIPTION\",\"reporter\":\"$WORKER_ID\"},\"id\":1}")
    echo "🚫 Blocker reported: $DESCRIPTION"
    ;;

  # === Voting ===
  vote-create)
    DECISION="$1"
    OPTIONS="$2"
    IFS=',' read -ra OPTS <<< "$OPTIONS"
    OPTS_JSON=$(printf '"%s",' "${OPTS[@]}" | sed 's/,$//')
    RESPONSE=$(send_as_worker "{\"method\":\"create_vote\",\"params\":{\"decision\":\"$DECISION\",\"options\":[$OPTS_JSON]},\"id\":1}")
    echo "🗳️  Vote created: $DECISION"
    echo "   Options: ${OPTS[*]}"
    ;;

  vote-cast)
    VOTE_ID="$1"
    OPTION="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"cast_vote\",\"params\":{\"voteId\":\"$VOTE_ID\",\"option\":\"$OPTION\"},\"id\":1}")
    echo "✓ Vote recorded: $OPTION"
    ;;

  vote-status)
    VOTE_ID="$1"
    RESPONSE=$(send_request "{\"method\":\"get_vote_status\",\"params\":{\"voteId\":\"$VOTE_ID\"},\"id\":1}")
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    v = data.get('result', {})
    if v:
        print(f\"Vote: {v.get('decision', '?')}\")
        print(f\"Status: {v.get('status', '?')}\")
        print(f\"Votes: {len(v.get('votes', {}))} of {v.get('quorum', '?')}\")
        if v.get('result'):
            print(f\"Result: {v['result'].get('winner', 'Tie')}\")
    else:
        print('Vote not found')
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null
    ;;

  votes)
    RESPONSE=$(send_request '{"method":"get_active_votes","id":1}')
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    votes = data.get('result', [])
    if not votes:
        print('No active votes')
    else:
        for v in votes:
            print(f\"[{v['id']}] {v['decision']}\")
            print(f\"    Options: {', '.join(v['options'])}\")
            print(f\"    Votes: {v.get('currentVotes', 0)}/{v['quorum']}\")
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null
    ;;

  # === Info ===
  workers)
    RESPONSE=$(send_request '{"method":"get_workers","id":1}')
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    workers = data.get('result', [])
    if not workers:
        print('No active workers')
    else:
        print('Active workers:')
        for w in workers:
            last = w.get('lastHeartbeat', '?')[:19] if w.get('lastHeartbeat') else '?'
            print(f\"  - {w['id']} (last heartbeat: {last})\")
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null
    ;;

  status)
    RESPONSE=$(send_request '{"method":"get_stats","id":1}')
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    stats = data.get('result', {})
    print(f\"Workers: {stats.get('workers', 0)}\")
    print(f\"Active votes: {stats.get('activeVotes', 0)}\")
    ps = stats.get('pubsub', {})
    print(f\"Connected clients: {ps.get('clients', 0)}\")
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null
    ;;

  *)
    echo "Usage: wt-sync.sh <command> [args]"
    echo ""
    echo "Communication:"
    echo "  broadcast \"message\"         Send to all"
    echo "  send <worker> \"message\"     Send to specific worker"
    echo ""
    echo "Tasks:"
    echo "  task-started <id>           Mark task as started"
    echo "  task-progress <id> \"msg\"    Update progress"
    echo "  task-completed <id> \"msg\"   Mark as complete"
    echo ""
    echo "Findings:"
    echo "  finding <severity> \"desc\"   Report finding (low/medium/high/critical)"
    echo "  blocker \"description\"       Report blocker"
    echo ""
    echo "Voting:"
    echo "  vote-create \"decision\" \"op1,op2,...\"  Create vote"
    echo "  vote-cast <id> \"option\"               Cast vote"
    echo "  vote-status <id>                      View status"
    echo "  votes                                 List active votes"
    echo ""
    echo "Info:"
    echo "  workers                      List active workers"
    echo "  status                       Daemon general status"
    exit 1
    ;;
esac

exit 0
