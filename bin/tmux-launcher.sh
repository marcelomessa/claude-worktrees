#!/bin/bash
# =============================================================================
# TMUX LAUNCHER - Multi-Agent Claude Environment with Tmux
# =============================================================================
# Cria sessão tmux com múltiplas windows para workers Claude
# Suporta estrutura de projeto com .cwt/ ou modo legado (git worktrees)
#
# Uso: ./tmux-launcher.sh [--continue|-c] [--strict] [workspace1] [workspace2] ...
#   --continue, -c  Resume previous Claude sessions in each worker
#   --strict        Use Claude's native permissions (no --dangerously-skip-permissions)
# =============================================================================

# Parse arguments (preserve exported values from cwt)
CONTINUE_FLAG="${CONTINUE_FLAG:-}"
SKIP_PERMISSIONS="${SKIP_PERMISSIONS:-1}"  # Default: skip permissions, use bash-validator
WORKSPACES_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --continue|-c)
      CONTINUE_FLAG="--continue"
      shift
      ;;
    --strict)
      SKIP_PERMISSIONS=""  # Use Claude's native permissions
      shift
      ;;
    *)
      WORKSPACES_ARGS+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters (workspaces only)
set -- "${WORKSPACES_ARGS[@]}"

# Usar sessão do ambiente ou padrão
SESSION_NAME="${SESSION_NAME:-cwt}"
PULSER_INTERVAL=${PULSER_INTERVAL:-120}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
# LOG_DIR será definido após detectar PROJECT_ROOT
CWT_BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
CWT_CONFIG_DIR="$(cd "$CWT_BIN_DIR/../config" && pwd)"
CWT_TEMPLATES_DIR="$(cd "$CWT_BIN_DIR/../templates" && pwd)"
TMUX_CONF="$CWT_CONFIG_DIR/tmux.conf"

# Detectar se estamos em modo projeto (.cwt/) ou legado (git worktrees)
PROJECT_ROOT="${CWT_PROJECT_ROOT:-}"
PROJECT_MODE="legacy"

if [[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT/.cwt" ]]; then
  PROJECT_MODE="project"
  PROJECT_DIR="$PROJECT_ROOT"
  STATE_FILE="$PROJECT_ROOT/.cwt/state.json"
  WORKSPACES_FILE="$PROJECT_ROOT/.cwt/workers.txt"
  LOG_DIR="${CWT_LOG_DIR:-$PROJECT_ROOT/.cwt/logs}"
else
  PROJECT_DIR="${CWT_PROJECT:-$(pwd)}"
  STATE_FILE="/tmp/claude-wt-state.json"
  WORKSPACES_FILE="/tmp/cwt-workers-list.txt"
  LOG_DIR="${CWT_LOG_DIR:-/tmp/cwt-logs}"
fi

# ============================================================================
# FUNÇÕES DE DETECÇÃO - MODO PROJETO
# ============================================================================

# Detectar diretório do coordenador
detect_coordinator_dir() {
  # 1. Configurado em .cwt/config.json
  if [[ -f "$PROJECT_ROOT/.cwt/config.json" ]]; then
    local coord=$(jq -r '.coordinator // empty' "$PROJECT_ROOT/.cwt/config.json" 2>/dev/null)
    if [[ -n "$coord" && "$coord" != "null" ]]; then
      # Caso 1: coordinator é subdiretório (estrutura de projeto)
      if [[ -d "$PROJECT_ROOT/$coord" ]]; then
        echo "$coord"
        return
      fi
      # Caso 2: PROJECT_ROOT É o coordinator (cwt init dentro do repo)
      if [[ "$(basename "$PROJECT_ROOT")" == "$coord" && -d "$PROJECT_ROOT/.git" ]]; then
        echo "."
        return
      fi
    fi
  fi

  # 2. PROJECT_ROOT é um repo git (cwt init dentro do repo)
  if [[ -d "$PROJECT_ROOT/.git" ]]; then
    echo "."
    return
  fi

  # 3. Primeira pasta com .git/ completo (repo, não worktree)
  for dir in "$PROJECT_ROOT"/*/; do
    local name=$(basename "$dir")
    [[ "$name" == ".cwt" ]] && continue
    # .git/ como diretório = repo principal
    if [[ -d "$dir/.git" ]]; then
      echo "$name"
      return
    fi
  done
}

# Detectar workers (APENAS worktrees do coordenador, não outros repos)
detect_workers_project() {
  local coord_dir=$(detect_coordinator_dir)
  local coord_path="$PROJECT_ROOT/$coord_dir"

  # Se não tem coordenador, não há workers
  [[ -z "$coord_dir" || ! -d "$coord_path" ]] && return

  # Listar worktrees do coordenador
  git -C "$coord_path" worktree list --porcelain 2>/dev/null | grep "^worktree " | cut -d' ' -f2- | while read -r wt_path; do
    # Pular o próprio coordenador
    [[ "$wt_path" == "$coord_path" ]] && continue

    # Verificar se está dentro do PROJECT_ROOT
    if [[ "$wt_path" == "$PROJECT_ROOT"/* ]]; then
      basename "$wt_path"
    fi
  done
}

# ============================================================================
# FUNÇÕES DE DETECÇÃO - MODO LEGADO (git worktrees)
# ============================================================================

detect_workers_legacy() {
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
    echo "Erro: Não está em um repositório git" >&2
    return 1
  fi

  local main_wt=$(git -C "$PROJECT_DIR" worktree list --porcelain | head -1 | cut -d' ' -f2-)

  git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2- | while read -r wt; do
    if [[ "$wt" != "$main_wt" && -n "$wt" ]]; then
      basename "$wt" | sed 's/^workspace-//'
    fi
  done
}

# ============================================================================
# SETUP DE TEMPLATES E PROMPTS INICIAIS
# ============================================================================

# Instalar CLAUDE.md se não existir
install_claude_md() {
  local target_dir="$1"
  local role="$2"  # "coordinator" ou "worker"
  local worker_id="$3"

  # Se já existe CLAUDE.md, não sobrescrever
  [[ -f "$target_dir/CLAUDE.md" ]] && return 0

  local template=""
  if [[ "$role" == "coordinator" ]]; then
    template="$CWT_TEMPLATES_DIR/CLAUDE.coord.md"
  else
    template="$CWT_TEMPLATES_DIR/CLAUDE.worker.md"
  fi

  if [[ -f "$template" ]]; then
    # Copiar e substituir WORKER_ID
    sed "s/WORKER_ID/$worker_id/g" "$template" > "$target_dir/CLAUDE.md"
    echo "   📄 CLAUDE.md instalado em $target_dir"
  fi
}

# Instalar settings.json com permissões e hooks
install_settings() {
  local target_dir="$1"
  local role="$2"  # "coordinator" ou "worker"
  local worker_id="$3"

  local claude_dir="$target_dir/.claude"
  local settings_file="$claude_dir/settings.json"

  # Criar diretório .claude se não existir
  mkdir -p "$claude_dir"

  # Escolher template
  local template=""
  if [[ "$role" == "coordinator" ]]; then
    template="$CWT_TEMPLATES_DIR/settings.coord.json"
  else
    template="$CWT_TEMPLATES_DIR/settings.worker.json"
  fi

  if [[ -f "$template" ]]; then
    # Copiar e substituir WORKER_NAME
    sed "s/WORKER_NAME/$worker_id/g" "$template" > "$settings_file"
    echo "   ⚙️  settings.json instalado em $claude_dir"
  else
    echo "   ⚠️  Template não encontrado: $template"
  fi
}

# Gerar prompt inicial para o coordenador
get_coordinator_prompt() {
  local workers_list="$1"
  cat << EOF
You are the COORDINATOR of a multi-Claude team.

CRITICAL: You COORDINATE, you do NOT implement. DELEGATE tasks to workers!

Available workers: $workers_list

Commands:
- wt-task <worker> "task" - Send task to worker
- wt-msg check - Check for messages
- wt-msg read - Read messages from workers
- tmux capture-pane -t 1 -p | tail -20 - See what worker 1 is doing

Workflow:
1. Receive request from user
2. Break into worker tasks
3. Send via wt-task
4. Monitor via wt-msg and tmux capture-pane
5. Integrate when ready

Waiting for instructions.
EOF
}

# Gerar prompt inicial para worker
get_worker_prompt() {
  local worker_id="$1"
  cat << EOF
You are worker [$worker_id].

Check for tasks:
  wt-msg check
  wt-msg read

When done with a task:
  wt-msg send coord "task X completed"

Waiting for tasks from coordinator...
EOF
}

# ============================================================================
# FUNÇÕES DE ESPERA
# ============================================================================

# Aguardar Claude estar pronto (detectar prompt)
wait_for_claude() {
  local session="$1"
  local window="$2"
  local max_attempts="${3:-30}"  # 30 tentativas = ~15 segundos
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    # Capturar últimas linhas do pane
    local output=$(tmux capture-pane -t "$session:$window" -p -S -5 2>/dev/null)

    # Claude pronto: mostra ">" prompt ou está aguardando input
    # Claude falhou: mostra "%" (zsh) ou erro
    if echo "$output" | grep -qE "^>" 2>/dev/null; then
      return 0  # Claude pronto
    fi

    # Se voltou ao shell (% prompt após comando claude), falhou
    if echo "$output" | grep -qE "^[^>]*%[[:space:]]*$" 2>/dev/null && \
       echo "$output" | grep -qE "(No conversation|Error|failed)" 2>/dev/null; then
      return 1  # Claude falhou
    fi

    sleep 0.5
    ((attempt++))
  done

  return 1  # Timeout
}

# ============================================================================
# INICIALIZAÇÃO
# ============================================================================

echo "═══════════════════════════════════════════════════════════════"
echo " 🖥️  Claude Multi-Agent Tmux Environment"
echo "═══════════════════════════════════════════════════════════════"
echo " Mode: $PROJECT_MODE"
echo " Session: $SESSION_NAME"
[[ -n "$CONTINUE_FLAG" ]] && echo " Resume: enabled (--continue)"

# Determinar workers
if [[ $# -gt 0 ]]; then
  WORKSPACES=("$@")
elif [[ "$PROJECT_MODE" == "project" ]]; then
  # Alternativa compatível com bash 3.x (macOS default)
  WORKSPACES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && WORKSPACES+=("$line")
  done < <(detect_workers_project)
else
  WORKSPACES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && WORKSPACES+=("$line")
  done < <(detect_workers_legacy)
fi

if [[ ${#WORKSPACES[@]} -eq 0 ]]; then
  echo ""
  echo "ℹ️  Nenhum worker encontrado - iniciando só com coordinator"
  echo "   Para criar workers depois: wt-init worker1 worker2"
fi

# Determinar diretório do coordenador
if [[ "$PROJECT_MODE" == "project" ]]; then
  COORD_DIR_NAME=$(detect_coordinator_dir)
  COORD_DIR="$PROJECT_ROOT/$COORD_DIR_NAME"
  if [[ ! -d "$COORD_DIR" ]]; then
    echo "⚠️  Diretório do coordenador não encontrado: $COORD_DIR_NAME"
    echo "   Clone o repo principal: git clone <url> main"
    exit 1
  fi
else
  COORD_DIR=$(git -C "$PROJECT_DIR" worktree list --porcelain | head -1 | cut -d' ' -f2-)
  COORD_DIR_NAME=$(basename "$COORD_DIR")
fi

echo " Coordinator: $COORD_DIR_NAME"
echo " Workers: ${WORKSPACES[*]}"
echo " State: $STATE_FILE"
echo " Mouse scroll: enabled"
echo "═══════════════════════════════════════════════════════════════"

# Verificar se sessão já existe
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "⚠️  Sessão '$SESSION_NAME' já existe."
  echo "   Usar: tmux attach -t $SESSION_NAME  (para reconectar)"
  echo "   Usar: tmux kill-session -t $SESSION_NAME  (para encerrar)"
  exit 1
fi

# Salvar lista de workspaces
mkdir -p "$(dirname "$WORKSPACES_FILE")"
printf '%s\n' "${WORKSPACES[@]}" > "$WORKSPACES_FILE"

# Inicializar state se necessário
if [[ ! -f "$STATE_FILE" ]]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  echo '{"workers":{},"messages":[]}' > "$STATE_FILE"
fi

# Criar diretório de logs
mkdir -p "$LOG_DIR"
echo "📝 Logs: $LOG_DIR/cwt-*-$TIMESTAMP.log"

# ============================================================================
# INICIAR DAEMON DE COMUNICAÇÃO
# ============================================================================

CWT_DAEMON_DIR="$(cd "$CWT_BIN_DIR/../daemon" && pwd)"
DAEMON_LOG="$LOG_DIR/cwt-daemon-$TIMESTAMP.log"
DAEMON_PID_FILE="$PROJECT_ROOT/.cwt/daemon.pid"
CWT_SOCKET="$PROJECT_ROOT/.cwt/cwt.sock"

# Parar daemon anterior se existir
if [[ -f "$DAEMON_PID_FILE" ]]; then
  OLD_PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "🔄 Parando daemon anterior (PID: $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null
    sleep 1
  fi
  rm -f "$DAEMON_PID_FILE"
fi

# Remover socket antigo
rm -f "$CWT_SOCKET"

# Iniciar daemon
if [[ -f "$CWT_DAEMON_DIR/index.js" ]] && command -v node &>/dev/null; then
  echo "🚀 Iniciando daemon de comunicação..."
  nohup node "$CWT_DAEMON_DIR/index.js" "$PROJECT_ROOT" > "$DAEMON_LOG" 2>&1 &
  DAEMON_PID=$!
  sleep 1

  # Verificar se iniciou corretamente
  if kill -0 "$DAEMON_PID" 2>/dev/null && [[ -S "$CWT_SOCKET" ]]; then
    echo "   ✅ Daemon rodando (PID: $DAEMON_PID)"
    echo "   📡 Socket: $CWT_SOCKET"
  else
    echo "   ⚠️  Daemon pode não ter iniciado corretamente"
    echo "   📄 Log: $DAEMON_LOG"
  fi
else
  echo "⚠️  Daemon não disponível (node não encontrado ou daemon/index.js ausente)"
  echo "   Comunicação em tempo real desabilitada"
fi

# Exportar variáveis para os workers
export CWT_SOCKET
export CWT_PROJECT_ROOT="$PROJECT_ROOT"

# ============================================================================
# CRIAR SESSÃO TMUX
# ============================================================================

echo "📺 Criando sessão tmux..."
if [[ -f "$TMUX_CONF" ]]; then
  tmux -f "$TMUX_CONF" new-session -d -s "$SESSION_NAME" -n "coordinator"
else
  tmux new-session -d -s "$SESSION_NAME" -n "coordinator"
fi
sleep 0.3

# Habilitar logging para coordinator
tmux pipe-pane -t "$SESSION_NAME:0" -o "cat >> '$LOG_DIR/cwt-coordinator-$TIMESTAMP.log'"

# Verificar branch do coordenador
CURRENT_BRANCH=$(git -C "$COORD_DIR" branch --show-current 2>/dev/null || echo 'unknown')

echo ""
echo "📋 Layout:"
echo "   0: coordinator ($COORD_DIR_NAME) - $CURRENT_BRANCH"

# Window 0: Coordinator
echo "🎯 Configurando coordinator..."

# Instalar CLAUDE.md se não existir
install_claude_md "$COORD_DIR" "coordinator" "coordinator"

tmux send-keys -t "$SESSION_NAME:0" "export CLAUDE_WORKER_ID='coordinator'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "export CWT_PROJECT_ROOT='$PROJECT_ROOT'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "export CWT_SOCKET='$CWT_SOCKET'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "cd '$COORD_DIR'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "echo '🎯 COORDINATOR - $COORD_DIR_NAME ($CURRENT_BRANCH)'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "claude ${SKIP_PERMISSIONS:+--dangerously-skip-permissions} $CONTINUE_FLAG" Enter

# Criar window para cada worker
WINDOW_NUM=1
WORKER_WINDOWS=()
for workspace in "${WORKSPACES[@]}"; do
  # Determinar diretório do worker
  if [[ "$PROJECT_MODE" == "project" ]]; then
    WORKSPACE_DIR="$PROJECT_ROOT/$workspace"
  else
    # Modo legado: buscar worktree
    WORKSPACE_DIR=""
    while IFS= read -r wt; do
      wt_name=$(basename "$wt" | sed 's/^workspace-//')
      if [[ "$wt_name" == "$workspace" || "$(basename "$wt")" == "$workspace" ]]; then
        WORKSPACE_DIR="$wt"
        break
      fi
    done < <(git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-)

    [[ -z "$WORKSPACE_DIR" ]] && WORKSPACE_DIR="$(dirname "$COORD_DIR")/workspace-$workspace"
  fi

  if [[ ! -d "$WORKSPACE_DIR" ]]; then
    echo "   ⚠️  $WINDOW_NUM: $workspace (NÃO ENCONTRADO)"
    ((WINDOW_NUM++))
    continue
  fi

  # Branch do worker
  wt_branch=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || echo '?')
  echo "   $WINDOW_NUM: $workspace - $wt_branch"

  # Instalar CLAUDE.md se não existir
  install_claude_md "$WORKSPACE_DIR" "worker" "$workspace"

  # Criar window
  tmux new-window -t "$SESSION_NAME" -n "$workspace"
  sleep 0.3

  # Logging
  tmux pipe-pane -t "$SESSION_NAME:$WINDOW_NUM" -o "cat >> '$LOG_DIR/cwt-$workspace-$TIMESTAMP.log'"

  # Configurar
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CLAUDE_WORKER_ID='$workspace'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CWT_PROJECT_ROOT='$PROJECT_ROOT'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CWT_SOCKET='$CWT_SOCKET'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "cd '$WORKSPACE_DIR'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "claude ${SKIP_PERMISSIONS:+--dangerously-skip-permissions} $CONTINUE_FLAG" Enter

  # Guardar info para enviar prompt depois
  WORKER_WINDOWS+=("$WINDOW_NUM:$workspace")

  ((WINDOW_NUM++))
done

# Enviar prompts iniciais para coordinator e workers (após todos iniciarem)
echo "⏳ Aguardando Claude iniciar..."

# Aguardar e enviar prompt para coordinator
echo "   ⏳ Aguardando coordinator..."
if wait_for_claude "$SESSION_NAME" 0; then
  # Se --continue foi usado e funcionou, não enviar prompt (já tem contexto)
  if [[ -z "$CONTINUE_FLAG" ]]; then
    COORD_PROMPT=$(get_coordinator_prompt "${WORKSPACES[*]}")
    tmux send-keys -t "$SESSION_NAME:0" "$COORD_PROMPT"
    sleep 0.1
    tmux send-keys -t "$SESSION_NAME:0" "" C-m
  fi
  echo "   ✅ Coordinator pronto"
else
  # Se --continue falhou, reiniciar sem a flag
  if [[ -n "$CONTINUE_FLAG" ]]; then
    echo "   ⚠️  Coordinator: --continue falhou, reiniciando..."
    tmux send-keys -t "$SESSION_NAME:0" "claude ${SKIP_PERMISSIONS:+--dangerously-skip-permissions}" Enter
    if wait_for_claude "$SESSION_NAME" 0; then
      COORD_PROMPT=$(get_coordinator_prompt "${WORKSPACES[*]}")
      tmux send-keys -t "$SESSION_NAME:0" "$COORD_PROMPT"
      sleep 0.1
      tmux send-keys -t "$SESSION_NAME:0" "" C-m
      echo "   ✅ Coordinator pronto (fallback)"
    else
      echo "   ⚠️  Coordinator: Claude não iniciou (verifique a window 0)"
    fi
  else
    echo "   ⚠️  Coordinator: Claude não iniciou (verifique a window 0)"
  fi
fi

# Aguardar e enviar prompts para workers
for worker_info in "${WORKER_WINDOWS[@]}"; do
  win_num="${worker_info%%:*}"
  worker_id="${worker_info#*:}"
  echo "   ⏳ Aguardando $worker_id..."
  if wait_for_claude "$SESSION_NAME" "$win_num"; then
    # Se --continue foi usado e funcionou, não enviar prompt (já tem contexto)
    if [[ -z "$CONTINUE_FLAG" ]]; then
      WORKER_PROMPT=$(get_worker_prompt "$worker_id")
      tmux send-keys -t "$SESSION_NAME:$win_num" "$WORKER_PROMPT"
      sleep 0.1
      tmux send-keys -t "$SESSION_NAME:$win_num" "" C-m
    fi
    echo "   ✅ $worker_id pronto"
  else
    # Se --continue falhou, reiniciar sem a flag
    if [[ -n "$CONTINUE_FLAG" ]]; then
      echo "   ⚠️  $worker_id: --continue falhou, reiniciando..."
      tmux send-keys -t "$SESSION_NAME:$win_num" "claude ${SKIP_PERMISSIONS:+--dangerously-skip-permissions}" Enter
      if wait_for_claude "$SESSION_NAME" "$win_num"; then
        WORKER_PROMPT=$(get_worker_prompt "$worker_id")
        tmux send-keys -t "$SESSION_NAME:$win_num" "$WORKER_PROMPT"
        sleep 0.1
        tmux send-keys -t "$SESSION_NAME:$win_num" "" C-m
        echo "   ✅ $worker_id pronto (fallback)"
      else
        echo "   ⚠️  $worker_id: Claude não iniciou (verifique a window $win_num)"
      fi
    else
      echo "   ⚠️  $worker_id: Claude não iniciou (verifique a window $win_num)"
    fi
  fi
done

# Window final: Monitor
echo "   $WINDOW_NUM: monitor"
tmux new-window -t "$SESSION_NAME" -n "monitor"
sleep 0.2
tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "cd '$COORD_DIR' && echo '📊 Monitor - $SESSION_NAME'" Enter

# ============================================================================
# INICIAR PULSER (monitor de atividade)
# ============================================================================

PULSER_SCRIPT="$CWT_BIN_DIR/tmux-pulser.sh"
PULSER_LOG="$LOG_DIR/cwt-pulser-$TIMESTAMP.log"
PULSER_PID_FILE="$PROJECT_ROOT/.cwt/pulser.pid"

# Parar pulser anterior se existir
if [[ -f "$PULSER_PID_FILE" ]]; then
  OLD_PID=$(cat "$PULSER_PID_FILE" 2>/dev/null)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null
  fi
  rm -f "$PULSER_PID_FILE"
fi

# Iniciar pulser em background
if [[ -f "$PULSER_SCRIPT" ]]; then
  echo ""
  echo "🔄 Iniciando pulser..."
  SESSION_NAME="$SESSION_NAME" CWT_PROJECT_ROOT="$PROJECT_ROOT" \
    nohup "$PULSER_SCRIPT" >> "$PULSER_LOG" 2>&1 &
  echo $! > "$PULSER_PID_FILE"
  sleep 0.3
  if kill -0 "$(cat "$PULSER_PID_FILE")" 2>/dev/null; then
    echo "   ✅ Pulser ativo (intervalo: ${PULSER_INTERVAL:-120}s)"
  fi
fi

echo ""
echo "✅ Ambiente criado!"
echo ""
echo "📋 Atalhos tmux (Ctrl+b é o prefix):"
echo "   Ctrl+b n    Próxima window"
echo "   Ctrl+b p    Window anterior"
echo "   Ctrl+b 0-9  Ir para window N"
echo "   Ctrl+b d    Desconectar"
echo ""

# Selecionar window do coordinator antes de conectar
tmux select-window -t "$SESSION_NAME:0"

# Conectar
sleep 0.5
exec tmux attach -t "$SESSION_NAME"
