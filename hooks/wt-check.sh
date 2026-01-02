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
    echo "wt-msg send coord \"CONTEXT RESET - Done: [X] | Doing: [Y] | Plan: [Z] | Decisions: [W]\""
    echo ""
  fi

  if ! check_daemon; then
    return
  fi

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

  # Registrar heartbeat
  send_as_worker '{"method":"heartbeat","id":1}' >/dev/null

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
