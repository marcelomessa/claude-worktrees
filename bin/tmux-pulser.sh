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
      log "💰 Billing cache atualizado"
    fi
  fi
}

> "$LOG_FILE"
log "🔄 Tmux Pulser iniciado"
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

  # Se há input pendente (texto digitado esperando Enter)
  # TODO: Detectar se é autosugestão do Claude (tem códigos ANSI dim/itálico)
  # Por enquanto: workers executam após threshold, coordinator nunca
  if [[ "$has_pending_input" == "true" ]]; then
    if [[ "$window_name" == "coordinator" ]]; then
      # Coordinator: nunca auto-submeter input pendente (pode ser autosugestão)
      log "   ⏸️  Input pendente em coordinator - aguardando humano"
      return 1
    elif [[ $idle_secs -gt $IDLE_THRESHOLD ]]; then
      # Worker: submeter após threshold (provavelmente comando do coordinator)
      log "   ➡️  Enviando Enter para $window_name (input pendente + idle)"
      tmux send-keys -t "$SESSION_NAME:$window_num" "" C-m
      return 0
    else
      log "   ⏳  Input pendente em $window_name - aguardando threshold"
      return 1
    fi
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
      # Worker: only notify if there are pending messages
      # Don't send wt-msg check - it wastes tokens when nothing pending
      if [[ "$has_msgs" == "true" ]]; then
        cmd="wt-msg read"
      fi
      # If no messages, do nothing - let workers communicate naturally
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
  # Verificar se sessão tmux existe
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "❌ Sessão '$SESSION_NAME' não encontrada. Encerrando."
    exit 1
  fi

  # Verificar se diretório do projeto ainda existe (evita pulser órfão)
  if [[ -n "$CWT_ROOT" && ! -d "$CWT_ROOT/.cwt" ]]; then
    log "❌ Projeto '$CWT_ROOT' não existe mais. Encerrando pulser órfão."
    exit 1
  fi

  # Update billing cache periodically
  update_billing_cache

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
