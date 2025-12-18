#!/bin/bash
# =============================================================================
# INIT-WORKER - Hook executado ao iniciar sessão Claude
# =============================================================================
# Registra o worker e verifica mensagens pendentes
# =============================================================================

WORKER_ID="${CLAUDE_WORKER_ID:-$(basename "$PWD")}"
STATE_FILE="/tmp/claude-wt-state.json"

# Initialize state if needed
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"workers":{},"messages":[]}' > "$STATE_FILE"
fi

# Register worker
jq ".workers[\"$WORKER_ID\"] = {\"status\":\"active\",\"started\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "═══════════════════════════════════════"
echo " CLAUDE WORKER: $WORKER_ID"
echo "═══════════════════════════════════════"

# Check for pending messages
if command -v wt-msg &>/dev/null; then
  wt-msg check 2>/dev/null || true
fi
