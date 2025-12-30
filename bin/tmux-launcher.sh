#!/bin/bash
# =============================================================================
# TMUX LAUNCHER - Multi-Agent Claude Environment with Tmux
# =============================================================================
# Cria sessão tmux com múltiplas windows para workers Claude
# Inclui pulser que monitora e envia comandos para workers inativos
#
# Uso: ./tmux-launcher.sh [workspace1] [workspace2] ...
#      ./tmux-launcher.sh security-features ui-performance data-intelligence
#      ./tmux-launcher.sh  # usa workspaces padrão
# =============================================================================

SESSION_NAME="cwt"
PULSER_INTERVAL=${PULSER_INTERVAL:-30}
WORKSPACES_FILE="/tmp/cwt-workers-list.txt"
LOG_DIR="${CWT_LOG_DIR:-$HOME/repos/terminal_logs}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Detectar diretório base do projeto (onde está o .git principal)
PROJECT_DIR="${CWT_PROJECT:-$(pwd)}"
if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  echo "Erro: Não está em um repositório git"
  echo "Use: cwt start   (a partir de um repo git)"
  echo "Ou:  CWT_PROJECT=/caminho/repo cwt start"
  exit 1
fi

# Parse arguments ou detectar worktrees automaticamente
if [[ $# -gt 0 ]]; then
  WORKSPACES=("$@")
  BASE_DIR="$PROJECT_DIR"
else
  # Detectar worktrees automaticamente
  MAIN_WORKTREE=$(git -C "$PROJECT_DIR" worktree list --porcelain | head -1 | cut -d' ' -f2-)
  BASE_DIR=$(dirname "$MAIN_WORKTREE")

  # Pegar todos worktrees exceto o principal
  WORKSPACES=()
  while IFS= read -r wt; do
    if [[ "$wt" != "$MAIN_WORKTREE" && -n "$wt" ]]; then
      name=$(basename "$wt" | sed 's/^workspace-//')
      WORKSPACES+=("$name")
    fi
  done < <(git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-)

  if [[ ${#WORKSPACES[@]} -eq 0 ]]; then
    echo "Nenhum worktree encontrado além do principal"
    echo "Crie worktrees com: git worktree add ../workspace-nome -b feature/nome"
    exit 1
  fi
fi

echo "═══════════════════════════════════════════════════════════════"
echo " 🖥️  Claude Multi-Agent Tmux Environment"
echo "═══════════════════════════════════════════════════════════════"
echo " Coordinator: window 0"
echo " Workers: ${WORKSPACES[*]}"
echo " Session: $SESSION_NAME"
echo "═══════════════════════════════════════════════════════════════"

# Verificar se sessão já existe
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "⚠️  Sessão '$SESSION_NAME' já existe."
  echo "   Usar: tmux attach -t $SESSION_NAME  (para reconectar)"
  echo "   Usar: tmux kill-session -t $SESSION_NAME  (para encerrar)"
  exit 1
fi

# Salvar lista de workspaces para o pulser
printf '%s\n' "${WORKSPACES[@]}" > "$WORKSPACES_FILE"

# Criar diretório de logs se não existir
mkdir -p "$LOG_DIR"
echo "📝 Logs serão salvos em: $LOG_DIR/cwt-*-$TIMESTAMP.log"

# Criar sessão tmux com window 0 (coordinator)
echo "📺 Criando sessão tmux..."
tmux new-session -d -s "$SESSION_NAME" -n "coordinator"
sleep 0.3

# Habilitar logging para coordinator
tmux pipe-pane -t "$SESSION_NAME:0" -o "cat >> '$LOG_DIR/cwt-coordinator-$TIMESTAMP.log'"

# Verificar branch atual do coordenador
CURRENT_BRANCH=$(git -C "$MAIN_WORKTREE" branch --show-current 2>/dev/null || echo 'unknown')
echo " Coordinator branch: $CURRENT_BRANCH"

# Se --base foi especificado e é diferente da atual, avisar
if [[ -n "$BASE_BRANCH" && "$BASE_BRANCH" != "$CURRENT_BRANCH" ]]; then
  echo ""
  echo "⚠️  Branch atual ($CURRENT_BRANCH) difere da base ($BASE_BRANCH)"
  echo "   O coordenador NÃO fará checkout automático."
  echo "   Se necessário, mude manualmente: git checkout $BASE_BRANCH"
  echo ""
fi

# Mostrar branches dos worktrees
echo ""
echo "📋 Branches dos worktrees:"
echo "   coordinator: $CURRENT_BRANCH"
for workspace in "${WORKSPACES[@]}"; do
  wt_branch=$(git -C "$PROJECT_DIR" worktree list | grep -E "workspace-$workspace|/$workspace " | awk '{print $NF}' | tr -d '[]')
  echo "   $workspace: $wt_branch"
done
echo ""

# Window 0: Coordinator (worktree principal)
echo "🎯 Configurando coordinator..."
tmux send-keys -t "$SESSION_NAME:0" "export CLAUDE_WORKER_ID='coordinator'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "cd '$MAIN_WORKTREE'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "echo '🎯 COORDINATOR - Branch: $CURRENT_BRANCH'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "claude --dangerously-skip-permissions $CONTINUE_FLAG" Enter

# Criar window para cada worker
WINDOW_NUM=1
for workspace in "${WORKSPACES[@]}"; do
  echo "📦 Criando window para $workspace..."

  # Criar nova window
  tmux new-window -t "$SESSION_NAME" -n "$workspace"
  sleep 0.3

  # Habilitar logging para este worker
  tmux pipe-pane -t "$SESSION_NAME:$WINDOW_NUM" -o "cat >> '$LOG_DIR/cwt-$workspace-$TIMESTAMP.log'"

  # Buscar caminho real do worktree
  WORKSPACE_DIR=""
  while IFS= read -r wt; do
    wt_name=$(basename "$wt" | sed 's/^workspace-//')
    if [[ "$wt_name" == "$workspace" || "$(basename "$wt")" == "$workspace" || "$(basename "$wt")" == "workspace-$workspace" ]]; then
      WORKSPACE_DIR="$wt"
      break
    fi
  done < <(git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-)

  # Fallback
  if [[ -z "$WORKSPACE_DIR" ]]; then
    WORKSPACE_DIR="$BASE_DIR/workspace-$workspace"
  fi

  if [[ -d "$WORKSPACE_DIR" ]]; then
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CLAUDE_WORKER_ID='$workspace'" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "cd '$WORKSPACE_DIR'" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "claude --dangerously-skip-permissions $CONTINUE_FLAG" Enter
  else
    echo "⚠️  Workspace não encontrado: $workspace"
    tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "echo 'Workspace $workspace não encontrado'" Enter
  fi

  ((WINDOW_NUM++))
done

# Window final: Monitor
echo "📊 Criando window de monitor..."
tmux new-window -t "$SESSION_NAME" -n "monitor"
sleep 0.2
tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "cd '$MAIN_WORKTREE' && echo '📊 Monitor - Status dos workers' && .claude/wt-check.sh status 2>/dev/null || echo 'wt-check.sh não encontrado'" Enter

echo ""
echo "✅ Ambiente criado!"
echo ""
echo "📋 Layout das windows:"
echo "   0: coordinator"
for i in "${!WORKSPACES[@]}"; do
  echo "   $((i+1)): ${WORKSPACES[$i]}"
done
echo "   $WINDOW_NUM: monitor"
echo ""
echo "📋 Atalhos do tmux (Ctrl+b é o prefix):"
echo "   Ctrl+b n    Próxima window"
echo "   Ctrl+b p    Window anterior"
echo "   Ctrl+b 0-9  Ir para window N"
echo "   Ctrl+b w    Lista de windows"
echo "   Ctrl+b d    Desconectar"
echo ""

# Conectar à sessão
sleep 1
exec tmux attach -t "$SESSION_NAME"
