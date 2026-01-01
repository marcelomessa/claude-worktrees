#!/bin/bash
# =============================================================================
# WT-CHECK - Status de coordenação para CWT
# =============================================================================
# Usado pelos hooks do Claude para mostrar status de comunicação
#
# Usage:
#   wt-check.sh status    # Status completo (UserPromptSubmit)
#   wt-check.sh quick     # Verificação rápida (PostToolUse)
# =============================================================================

MODE="${1:-status}"
WORKER_ID="${CLAUDE_WORKER_ID:-$(basename "$PWD")}"

# Encontrar socket do projeto
find_socket() {
  # 1. Variável de ambiente
  if [[ -n "$CWT_SOCKET" && -S "$CWT_SOCKET" ]]; then
    echo "$CWT_SOCKET"
    return 0
  fi

  # 2. Subir árvore procurando .cwt/cwt.sock
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

# Se não tem socket, sair silenciosamente
[[ -z "$SOCKET" || ! -S "$SOCKET" ]] && exit 0

# Função para enviar request ao daemon
send_request() {
  echo "$1" | nc -w 1 -U "$SOCKET" 2>/dev/null
}

# Registrar worker e enviar request
send_as_worker() {
  local request="$1"
  (
    echo "{\"method\":\"register\",\"params\":{\"id\":\"$WORKER_ID\"},\"id\":0}"
    sleep 0.1
    echo "$request"
  ) | nc -w 2 -U "$SOCKET" 2>/dev/null | tail -1
}

# Verificar se daemon está respondendo
check_daemon() {
  local pong=$(echo '{"method":"ping","id":1}' | nc -w 1 -U "$SOCKET" 2>/dev/null)
  if echo "$pong" | grep -q "pong"; then
    return 0
  fi
  return 1
}

# =============================================================================
# STATUS MODE - Status completo (UserPromptSubmit)
# =============================================================================
mode_status() {
  if ! check_daemon; then
    echo "⚠️  Daemon offline - comunicação desabilitada"
    return
  fi

  echo "═══ CWT COORDINATION ($WORKER_ID) ═══"
  echo ""

  # Registrar heartbeat
  send_as_worker '{"method":"heartbeat","id":1}' >/dev/null

  # Obter mensagens não lidas
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

  if [[ "$msg_count" -gt 0 ]]; then
    echo "📬 $msg_count mensagem(s) pendente(s)"
    echo "   → wt-msg read"
    echo ""
  fi

  # Verificar votações ativas
  local votes=$(send_request '{"method":"get_active_votes","id":3}')
  local vote_count=$(echo "$votes" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('result', [])))
except:
    print(0)
" 2>/dev/null || echo 0)

  if [[ "$vote_count" -gt 0 ]]; then
    echo "🗳️  $vote_count votação(ões) ativa(s)"
    echo "$votes" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for v in data.get('result', []):
        print(f\"   [{v['id']}] {v['decision']}\")
        print(f\"       Opções: {', '.join(v['options'])} | Votos: {v.get('currentVotes', 0)}/{v['quorum']}\")
except: pass
" 2>/dev/null
    echo ""
  fi

  # Workers ativos
  local workers=$(send_request '{"method":"get_workers","id":4}')
  local worker_list=$(echo "$workers" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    workers = data.get('result', [])
    names = [w['id'] for w in workers]
    print(', '.join(names) if names else '')
except: pass
" 2>/dev/null)

  if [[ -n "$worker_list" ]]; then
    echo "👥 Workers ativos: $worker_list"
    echo ""
  fi

  echo "═══════════════════════════════════════"
}

# =============================================================================
# QUICK MODE - Verificação rápida (PostToolUse)
# =============================================================================
mode_quick() {
  if ! check_daemon; then
    return
  fi

  # Registrar heartbeat
  send_as_worker '{"method":"heartbeat","id":1}' >/dev/null

  local has_urgent=0

  # Verificar mensagens
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

  if [[ "$msg_count" -gt 0 ]]; then
    echo "📬 $msg_count msg - wt-msg read"
    has_urgent=1
  fi

  # Verificar votações
  local votes=$(send_request '{"method":"get_active_votes","id":3}')
  local vote_count=$(echo "$votes" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('result', [])))
except:
    print(0)
" 2>/dev/null || echo 0)

  if [[ "$vote_count" -gt 0 ]]; then
    echo "🗳️  $vote_count votação(ões) ativa(s)"
    has_urgent=1
  fi
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
