#!/bin/bash
# =============================================================================
# TMUX PULSER - Monitora workers Claude e envia comandos quando inativos
# =============================================================================
# Versão tmux do pulser original
# =============================================================================

# Detectar .cwt/ subindo a árvore de diretórios
find_cwt_root() {
  # 1. Variável de ambiente
  if [[ -n "$CWT_PROJECT_ROOT" && -d "$CWT_PROJECT_ROOT/.cwt" ]]; then
    echo "$CWT_PROJECT_ROOT"
    return 0
  fi

  # 2. Subir árvore
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

# Determinar arquivos de estado
CWT_ROOT=$(find_cwt_root)
if [[ -n "$CWT_ROOT" ]]; then
  PROJECT_NAME=$(basename "$CWT_ROOT")
  SESSION_NAME="${SESSION_NAME:-cwt-$PROJECT_NAME}"
  STATE_FILE="$CWT_ROOT/.cwt/state.json"
  WORKSPACES_FILE="$CWT_ROOT/.cwt/workers.txt"
else
  SESSION_NAME="${SESSION_NAME:-cwt}"
  STATE_FILE="/tmp/claude-wt-state.json"
  WORKSPACES_FILE="/tmp/cwt-workers-list.txt"
fi

INTERVAL="${PULSER_INTERVAL:-30}"
IDLE_THRESHOLD="${IDLE_THRESHOLD:-60}"
LOG_FILE="/tmp/cwt-pulser.log"

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

  # Detectar se Claude está esperando input
  # Indicadores: "bypass permissions" ou linha vazia após separador ────
  local waiting_input=false
  if echo "$content" | tail -3 | grep -qE 'bypass permissions|shift\+tab to cycle' 2>/dev/null; then
    waiting_input=true
  fi

  # Detectar se há texto no buffer de input (texto antes de ↵ send)
  local has_pending_input=false
  if echo "$content" | tail -5 | grep -qE '↵ send' 2>/dev/null; then
    has_pending_input=true
  fi

  # Detectar se Claude está processando
  # Indicadores: spinner, "Thinking", "Hatching", "Investigating", contador de tempo
  local is_busy=false
  if echo "$content" | tail -10 | grep -qE '⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|✻|Thinking|Working|Hatching|Investigating|Reading|Searching|Analyzing|[0-9]+m [0-9]+s|[0-9]+s \·' 2>/dev/null; then
    is_busy=true
    waiting_input=false
  fi

  # Detectar se há mensagens enfileiradas (indicador de que algo já está pendente)
  if echo "$content" | tail -5 | grep -qE 'Press up to edit queued|queued messages' 2>/dev/null; then
    is_busy=true
    waiting_input=false
  fi

  local has_msgs=false
  has_pending_messages "$window_name" && has_msgs=true

  log "   [$window_num] $window_name: idle=${idle_secs}s waiting=$waiting_input busy=$is_busy pending=$has_pending_input"

  # Se há input pendente (texto digitado esperando Enter), enviar Enter
  if [[ "$has_pending_input" == "true" ]]; then
    log "   ➡️  Enviando Enter para $window_name (input pendente)"
    tmux send-keys -t "$SESSION_NAME:$window_num" "" C-m
    return 0
  fi

  # Threshold diferente para coordinator (operado por humano) vs workers (autônomos)
  local threshold=$IDLE_THRESHOLD
  if [[ "$window_name" == "coordinator" ]]; then
    # Coordinator: só intervir após 5 minutos de inatividade, e APENAS se houver mensagens
    threshold="${COORD_IDLE_THRESHOLD:-300}"
  fi

  # Se está esperando input e idle por muito tempo
  if [[ "$waiting_input" == "true" && $idle_secs -gt $threshold ]]; then
    local cmd=""

    if [[ "$window_name" == "coordinator" ]]; then
      # Coordinator: SÓ notificar se houver mensagens pendentes dos workers
      if [[ "$has_msgs" == "true" ]]; then
        cmd="wt-msg read"
      fi
      # NÃO enviar "continue" para coordinator - deixar humano decidir
    else
      # Worker: verificar tarefas ou reportar status
      if [[ "$has_msgs" == "true" ]]; then
        cmd="wt-msg read"
      else
        cmd="wt-msg check"
      fi
    fi

    if [[ -n "$cmd" ]]; then
      log "   ➡️  Enviando '$cmd' para $window_name"
      tmux send-keys -t "$SESSION_NAME:$window_num" "$cmd"
      sleep 0.1
      tmux send-keys -t "$SESSION_NAME:$window_num" "" C-m
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

  log "🔍 Verificando agentes..."

  # Verificar coordinator (window 0)
  check_window 0 "coordinator"

  # Verificar workers
  if [[ -f "$WORKSPACES_FILE" ]]; then
    window_num=1
    while IFS= read -r worker; do
      [[ -n "$worker" ]] && check_window "$window_num" "$worker"
      ((window_num++))
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
