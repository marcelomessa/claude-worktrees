#!/bin/bash
# =============================================================================
# BASH-VALIDATOR - PreToolUse hook for command validation
# =============================================================================
#
# Este hook é a camada de proteção quando Claude roda com
# --dangerously-skip-permissions (modo padrão do CWT).
#
# Funcionalidades:
# 1. WORKER RESTRICTIONS: Bloqueia comandos perigosos para workers
# 2. SESSION OVERRIDES: Permite bloqueios/aprovações temporárias
#
# Exit codes:
#   0 - Permite comando
#   2 - Bloqueia (stderr mostrado ao Claude)
# =============================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

WORKER_ID="${CLAUDE_WORKER_ID:-}"

# =============================================================================
# FIND PROJECT ROOT
# =============================================================================
find_cwt_root() {
  if [[ -n "$CWT_PROJECT_ROOT" && -d "$CWT_PROJECT_ROOT/.cwt" ]]; then
    echo "$CWT_PROJECT_ROOT"
    return 0
  fi

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

CWT_ROOT=$(find_cwt_root)
OVERRIDES_FILE="${CWT_ROOT:-.}/.cwt/session-overrides.json"

block() {
  echo "❌ BLOCKED: $1" >&2
  exit 2
}

# =============================================================================
# WORKER RESTRICTIONS (quando skip-permissions está ativo)
# =============================================================================
if [[ "$WORKER_ID" != "coordinator" && -n "$WORKER_ID" ]]; then

  # Git: push, merge, rebase, checkout protected branches
  echo "$COMMAND" | grep -qE "git\s+push" && block "git push - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+merge" && block "git merge - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+rebase" && block "git rebase - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+checkout\s+(main|master|dev|develop)\b" && block "checkout branch protegida - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+reset\s+--hard" && block "git reset --hard - perigoso"

  # Azion CLI
  echo "$COMMAND" | grep -qE "azion\s+(deploy|delete|create|update|link|unlink)" && block "azion CLI - apenas coordinator"

  # Process control
  echo "$COMMAND" | grep -qE "\b(kill|pkill|killall)\b" && block "kill process - apenas coordinator"

fi

# =============================================================================
# UNIVERSAL RESTRICTIONS (todos, incluindo coordinator)
# =============================================================================
echo "$COMMAND" | grep -qE "rm\s+-rf\s+(/|~|\*)" && block "rm -rf perigoso"
echo "$COMMAND" | grep -qE ">\s*/dev/sd" && block "write to disk device"
echo "$COMMAND" | grep -qE "mkfs\." && block "mkfs proibido"
echo "$COMMAND" | grep -qE "dd\s+if=.*of=/dev" && block "dd to device"

# =============================================================================
# CHECK SESSION OVERRIDES
# =============================================================================

# Se não há arquivo de overrides, apenas passa
[[ ! -f "$OVERRIDES_FILE" ]] && exit 0

# Verificar expiração
EXPIRES=$(jq -r '.expires // empty' "$OVERRIDES_FILE" 2>/dev/null)
if [[ -n "$EXPIRES" && "$EXPIRES" != "null" ]]; then
  # Tentar converter para timestamp (macOS e Linux)
  EXPIRES_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES" +%s 2>/dev/null || \
               date -d "$EXPIRES" +%s 2>/dev/null || echo "")
  NOW_TS=$(date +%s)

  if [[ -n "$EXPIRES_TS" && "$NOW_TS" -gt "$EXPIRES_TS" ]]; then
    # Expirado, remover arquivo e sair
    rm -f "$OVERRIDES_FILE"
    exit 0
  fi
fi

# =============================================================================
# CHECK SESSION BLOCKS (adiciona restrições temporárias)
# =============================================================================
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == "null" ]] && continue
  if echo "$COMMAND" | grep -qE "$pattern"; then
    TASK=$(jq -r '.task // "sessão"' "$OVERRIDES_FILE" 2>/dev/null)
    block "Override de sessão ($TASK): $pattern"
  fi
done < <(jq -r '.overrides.block // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)

# =============================================================================
# CHECK AUTO-APPROVE (responde "ask" automaticamente via tmux)
# =============================================================================
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == "null" ]] && continue
  if echo "$COMMAND" | grep -qE "$pattern"; then
    # Este comando deve ser auto-aprovado
    # Spawnar processo em background para enviar "y" ao prompt ask
    if [[ -n "$TMUX_PANE" ]]; then
      (
        # Aguardar prompt aparecer
        sleep 0.3
        # Enviar "y" e Enter para aprovar
        tmux send-keys -t "$TMUX_PANE" "y" Enter 2>/dev/null
      ) &
      disown 2>/dev/null
    fi
    # Sair do loop, já encontrou match
    break
  fi
done < <(jq -r '.overrides.auto_approve // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)

# Permitir comando (continua para handling nativo do Claude)
exit 0
