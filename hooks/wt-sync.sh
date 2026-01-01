#!/bin/bash
# =============================================================================
# WT-SYNC - Sincronização de estado e comunicação para CWT
# =============================================================================
# Comandos para comunicação entre workers via daemon
#
# Usage:
#   wt-sync.sh broadcast "mensagem"           # Enviar para todos
#   wt-sync.sh send <worker> "mensagem"       # Enviar para worker específico
#   wt-sync.sh task-started <task-id>         # Marcar task como iniciada
#   wt-sync.sh task-progress <id> "update"    # Atualizar progresso
#   wt-sync.sh task-completed <id> "summary"  # Marcar como completa
#   wt-sync.sh finding <severity> "desc"      # Reportar finding
#   wt-sync.sh blocker "description"          # Reportar blocker
#   wt-sync.sh vote-create "decisão" "op1,op2"# Criar votação
#   wt-sync.sh vote-cast <id> "opção"         # Votar
#   wt-sync.sh workers                        # Listar workers ativos
# =============================================================================

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

if [[ -z "$SOCKET" || ! -S "$SOCKET" ]]; then
  echo "❌ Daemon não encontrado. Certifique-se que cwt está rodando."
  exit 1
fi

# Enviar request ao daemon
send_request() {
  echo "$1" | nc -w 2 -U "$SOCKET" 2>/dev/null
}

# Registrar e enviar
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
  # === Comunicação ===
  broadcast)
    MESSAGE="$1"
    RESPONSE=$(send_as_worker "{\"method\":\"broadcast\",\"params\":{\"data\":{\"message\":\"$MESSAGE\",\"from\":\"$WORKER_ID\"}},\"id\":1}")
    echo "📢 Broadcast enviado: $MESSAGE"
    ;;

  send)
    TO="$1"
    MESSAGE="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"send_message\",\"params\":{\"to\":\"$TO\",\"content\":\"$MESSAGE\",\"type\":\"direct\"},\"id\":1}")
    echo "📨 Mensagem enviada para $TO"
    ;;

  # === Tasks ===
  task-started)
    TASK_ID="$1"
    RESPONSE=$(send_as_worker "{\"method\":\"update_task\",\"params\":{\"taskId\":\"$TASK_ID\",\"updates\":{\"status\":\"in_progress\",\"assignedTo\":\"$WORKER_ID\"}},\"id\":1}")
    echo "▶️  Task $TASK_ID iniciada"
    ;;

  task-progress)
    TASK_ID="$1"
    PROGRESS="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"update_task\",\"params\":{\"taskId\":\"$TASK_ID\",\"updates\":{\"progress\":\"$PROGRESS\"}},\"id\":1}")
    echo "📝 Task $TASK_ID atualizada"
    ;;

  task-completed)
    TASK_ID="$1"
    SUMMARY="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"complete_task\",\"params\":{\"taskId\":\"$TASK_ID\",\"summary\":\"$SUMMARY\"},\"id\":1}")
    echo "✅ Task $TASK_ID completada"
    ;;

  # === Findings & Blockers ===
  finding)
    SEVERITY="$1"
    DESCRIPTION="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"add_finding\",\"params\":{\"severity\":\"$SEVERITY\",\"description\":\"$DESCRIPTION\",\"reporter\":\"$WORKER_ID\"},\"id\":1}")
    echo "🔍 Finding reportado [$SEVERITY]: $DESCRIPTION"
    ;;

  blocker)
    DESCRIPTION="$1"
    RESPONSE=$(send_as_worker "{\"method\":\"add_blocker\",\"params\":{\"description\":\"$DESCRIPTION\",\"reporter\":\"$WORKER_ID\"},\"id\":1}")
    echo "🚫 Blocker reportado: $DESCRIPTION"
    ;;

  # === Voting ===
  vote-create)
    DECISION="$1"
    OPTIONS="$2"
    IFS=',' read -ra OPTS <<< "$OPTIONS"
    OPTS_JSON=$(printf '"%s",' "${OPTS[@]}" | sed 's/,$//')
    RESPONSE=$(send_as_worker "{\"method\":\"create_vote\",\"params\":{\"decision\":\"$DECISION\",\"options\":[$OPTS_JSON]},\"id\":1}")
    echo "🗳️  Votação criada: $DECISION"
    echo "   Opções: ${OPTS[*]}"
    ;;

  vote-cast)
    VOTE_ID="$1"
    OPTION="$2"
    RESPONSE=$(send_as_worker "{\"method\":\"cast_vote\",\"params\":{\"voteId\":\"$VOTE_ID\",\"option\":\"$OPTION\"},\"id\":1}")
    echo "✓ Voto registrado: $OPTION"
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
        print(f\"Votação: {v.get('decision', '?')}\")
        print(f\"Status: {v.get('status', '?')}\")
        print(f\"Votos: {len(v.get('votes', {}))} de {v.get('quorum', '?')}\")
        if v.get('result'):
            print(f\"Resultado: {v['result'].get('winner', 'Empate')}\")
    else:
        print('Votação não encontrada')
except Exception as e:
    print(f'Erro: {e}')
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
        print('Nenhuma votação ativa')
    else:
        for v in votes:
            print(f\"[{v['id']}] {v['decision']}\")
            print(f\"    Opções: {', '.join(v['options'])}\")
            print(f\"    Votos: {v.get('currentVotes', 0)}/{v['quorum']}\")
except Exception as e:
    print(f'Erro: {e}')
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
        print('Nenhum worker ativo')
    else:
        print('Workers ativos:')
        for w in workers:
            last = w.get('lastHeartbeat', '?')[:19] if w.get('lastHeartbeat') else '?'
            print(f\"  - {w['id']} (último heartbeat: {last})\")
except Exception as e:
    print(f'Erro: {e}')
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
    print(f\"Votações ativas: {stats.get('activeVotes', 0)}\")
    ps = stats.get('pubsub', {})
    print(f\"Clientes conectados: {ps.get('clients', 0)}\")
except Exception as e:
    print(f'Erro: {e}')
" 2>/dev/null
    ;;

  *)
    echo "Usage: wt-sync.sh <command> [args]"
    echo ""
    echo "Comunicação:"
    echo "  broadcast \"mensagem\"        Enviar para todos"
    echo "  send <worker> \"mensagem\"    Enviar para worker específico"
    echo ""
    echo "Tasks:"
    echo "  task-started <id>           Marcar task como iniciada"
    echo "  task-progress <id> \"msg\"    Atualizar progresso"
    echo "  task-completed <id> \"msg\"   Marcar como completa"
    echo ""
    echo "Findings:"
    echo "  finding <severity> \"desc\"   Reportar finding (low/medium/high/critical)"
    echo "  blocker \"description\"       Reportar blocker"
    echo ""
    echo "Voting:"
    echo "  vote-create \"decisão\" \"op1,op2,...\"  Criar votação"
    echo "  vote-cast <id> \"opção\"               Votar"
    echo "  vote-status <id>                     Ver status"
    echo "  votes                                Listar votações ativas"
    echo ""
    echo "Info:"
    echo "  workers                      Listar workers ativos"
    echo "  status                       Status geral do daemon"
    exit 1
    ;;
esac

exit 0
