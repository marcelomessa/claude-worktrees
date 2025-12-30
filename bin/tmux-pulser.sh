#!/bin/bash
# =============================================================================
# TMUX PULSER - Monitora workers Claude e envia comandos quando inativos
# =============================================================================
# Versão tmux do pulser original
# =============================================================================

SESSION_NAME="${SESSION_NAME:-cwt}"
INTERVAL="${PULSER_INTERVAL:-30}"
IDLE_THRESHOLD="${IDLE_THRESHOLD:-60}"
LOG_FILE="/tmp/cwt-pulser.log"
WORKSPACES_FILE="/tmp/cwt-workers-list.txt"
STATE_FILE="$HOME/repos/mrmessa-claude-code/claude-worktrees/state.json"

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

> "$LOG_FILE"
log "🔄 Tmux Pulser iniciado"
log "   Session: $SESSION_NAME"
log "   Interval: ${INTERVAL}s"

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

  # Capturar conteúdo via tmux
  local content=$(tmux capture-pane -t "$SESSION_NAME:$window_num" -p 2>/dev/null)
  [[ -z "$content" ]] && return 1

  local last_time=$(extract_datetime "$content")
  local idle_secs=$(seconds_since "$last_time")

  local waiting_input=false
  if echo "$content" | tail -5 | grep -qE '^[>›»]|Human:|You:'; then
    waiting_input=true
  fi

  local has_msgs=false
  has_pending_messages "$window_name" && has_msgs=true

  log "   Window $window_num ($window_name): time=$last_time, idle=${idle_secs}s, waiting=$waiting_input, msgs=$has_msgs"

  if [[ "$waiting_input" == "true" && $idle_secs -gt $IDLE_THRESHOLD ]]; then
    if [[ "$has_msgs" == "true" ]]; then
      log "   ➡️  Sending 'act' to $window_name (has messages)"
      tmux send-keys -t "$SESSION_NAME:$window_num" "act" Enter
      return 0
    elif [[ $idle_secs -gt $((IDLE_THRESHOLD * 3)) ]]; then
      log "   ➡️  Sending 'status' to $window_name (very idle)"
      tmux send-keys -t "$SESSION_NAME:$window_num" "status" Enter
      return 0
    fi
  fi
  return 1
}

# Loop principal
while true; do
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "❌ Sessão '$SESSION_NAME' não encontrada. Encerrando."
    exit 1
  fi

  log "🔍 Verificando workers..."

  if [[ -f "$WORKSPACES_FILE" ]]; then
    window_num=1
    while IFS= read -r worker; do
      [[ -n "$worker" ]] && check_window "$window_num" "$worker" && ((window_num++))
    done < "$WORKSPACES_FILE"
  else
    log "⚠️  Arquivo de workspaces não encontrado"
    for i in {1..3}; do
      check_window "$i" "worker-$i" 2>/dev/null
    done
  fi

  log "💤 Aguardando ${INTERVAL}s..."
  sleep "$INTERVAL"
done
