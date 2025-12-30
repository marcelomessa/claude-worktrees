#!/bin/bash
# =============================================================================
# START WORKER - Launcher para sessões Claude com coordenação
# =============================================================================
# Uso: ./start-worker.sh [workspace] [--continue]
#
# Exemplos:
#   ./start-worker.sh security-features
#   ./start-worker.sh ui-performance --continue
#   ./start-worker.sh  # usa diretório atual
# =============================================================================

WORKSPACE="${1:-$(basename "$PWD")}"
SHIFT_ARGS=""

# Se primeiro arg é --continue, não é workspace
if [[ "$1" == "--continue" || "$1" == "-c" ]]; then
  WORKSPACE=$(basename "$PWD")
  SHIFT_ARGS="$@"
else
  shift
  SHIFT_ARGS="$@"
fi

# Determinar workspace directory
if [[ "$WORKSPACE" == workspace-* ]]; then
  WORKSPACE_DIR="$HOME/repos/mrmessa-claude-code/$WORKSPACE"
  WORKER_ID="${WORKSPACE#workspace-}"
elif [[ -d "$HOME/repos/mrmessa-claude-code/workspace-$WORKSPACE" ]]; then
  WORKSPACE_DIR="$HOME/repos/mrmessa-claude-code/workspace-$WORKSPACE"
  WORKER_ID="$WORKSPACE"
else
  WORKSPACE_DIR="$PWD"
  WORKER_ID="$WORKSPACE"
fi

export CLAUDE_WORKER_ID="$WORKER_ID"

echo "═══════════════════════════════════════"
echo " 🚀 Starting Claude Worker: $WORKER_ID"
echo "═══════════════════════════════════════"

# Inicializar sistema de coordenação
"$HOME/repos/mrmessa-claude-code/.claude/hooks/init-worker.sh"

echo ""
echo "📂 Workspace: $WORKSPACE_DIR"
echo "🔧 Worker ID: $WORKER_ID"
echo ""

# Iniciar Claude
cd "$WORKSPACE_DIR"
exec claude $SHIFT_ARGS
