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
# FIND PROJECT ROOT (needed early for coordinator detection)
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

# =============================================================================
# DETECT COORDINATOR (fallback quando CLAUDE_WORKER_ID não está definido)
# =============================================================================
if [[ -z "$WORKER_ID" && -n "$CWT_ROOT" && -f "$CWT_ROOT/.cwt/config.json" ]]; then
  COORD_DIR=$(jq -r '.coordinator // empty' "$CWT_ROOT/.cwt/config.json" 2>/dev/null)
  if [[ -n "$COORD_DIR" && "$COORD_DIR" != "null" ]]; then
    # Verificar se estamos no diretório do coordinator
    if [[ "$PWD" == *"/$COORD_DIR"* ]] || [[ "$PWD" == *"/$COORD_DIR" ]] || [[ "$(basename "$PWD")" == "$COORD_DIR" ]]; then
      WORKER_ID="coordinator"
    fi
  fi
fi

block() {
  echo "❌ BLOCKED: $1" >&2
  exit 2
}

# =============================================================================
# SESSION ALLOW (bypassa todas as restrições - verificar PRIMEIRO)
# =============================================================================
if [[ -f "$OVERRIDES_FILE" ]]; then
  # Verificar expiração primeiro
  EXPIRES=$(jq -r '.expires // empty' "$OVERRIDES_FILE" 2>/dev/null)
  OVERRIDE_VALID=true
  if [[ -n "$EXPIRES" && "$EXPIRES" != "null" ]]; then
    EXPIRES_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES" +%s 2>/dev/null || \
                 date -d "$EXPIRES" +%s 2>/dev/null || echo "")
    NOW_TS=$(date +%s)
    if [[ -n "$EXPIRES_TS" && "$NOW_TS" -gt "$EXPIRES_TS" ]]; then
      rm -f "$OVERRIDES_FILE"
      OVERRIDE_VALID=false
    fi
  fi

  if [[ "$OVERRIDE_VALID" == "true" ]]; then
    while IFS= read -r pattern; do
      [[ -z "$pattern" || "$pattern" == "null" ]] && continue
      if echo "$COMMAND" | grep -qE "$pattern"; then
        # Comando explicitamente permitido - bypass all checks
        exit 0
      fi
    done < <(jq -r '.overrides.allow // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)
  fi
fi

# =============================================================================
# WORKER RESTRICTIONS (quando skip-permissions está ativo)
# =============================================================================
if [[ "$WORKER_ID" != "coordinator" && -n "$WORKER_ID" ]]; then

  # Git: push, merge, rebase, checkout protected branches
  echo "$COMMAND" | grep -qE "git\s+push" && block "git push - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+merge" && block "git merge - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+rebase" && block "git rebase - apenas coordinator"
  echo "$COMMAND" | grep -qE "git\s+checkout\s+(main|master|dev|develop)\b" && block "checkout branch protegida - apenas coordinator"
  # git reset --hard agora bloqueado na seção UNIVERSAL para todos

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
echo "$COMMAND" | grep -qE "git\s+add\s+(-A|--all|\s\.(\s|$))" && block "git add -A/. - use arquivos específicos"

# =============================================================================
# GIT DESTRUCTIVE COMMANDS - PERDA IRREVERSÍVEL DE DADOS
# =============================================================================
# Estes comandos podem causar perda permanente de código não commitado.
# TODOS são bloqueados - usuário deve autorizar explicitamente.

# Pattern: git checkout -- <file>
echo "$COMMAND" | grep -qE "git\s+checkout\s+--\s" && block "PERDA DE DADOS: git checkout -- descarta mudanças permanentemente. Use 'git stash' para salvar, ou 'git commit' para preservar. AGUARDE o usuário autorizar."

# Pattern: git checkout .
echo "$COMMAND" | grep -qE "git\s+checkout\s+\.\s*$" && block "PERDA DE DADOS: git checkout . descarta TODAS as mudanças. Use 'git stash' ou 'git commit' primeiro. AGUARDE o usuário autorizar."

# Pattern: git checkout <hash> -- <file> (recupera versão antiga, PERDE atual!)
echo "$COMMAND" | grep -qE "git\s+checkout\s+[a-f0-9]+\s+--" && block "PERDA DE DADOS: git checkout <commit> -- <file> sobrescreve arquivo atual com versão antiga. Mudanças não commitadas serão PERDIDAS. Use 'git stash' primeiro, ou 'git show <commit>:<file>' para apenas visualizar. AGUARDE o usuário autorizar."

# Pattern: git checkout HEAD~N (volta commits, pode perder trabalho)
echo "$COMMAND" | grep -qE "git\s+checkout\s+HEAD~" && block "PERDA DE DADOS: git checkout HEAD~ pode descartar mudanças. Use 'git stash' primeiro. AGUARDE o usuário autorizar."

# Pattern: git checkout <branch> -- <file> (sobrescreve com versão de outra branch)
echo "$COMMAND" | grep -qE "git\s+checkout\s+\w+\s+--\s" && block "PERDA DE DADOS: git checkout <branch> -- <file> sobrescreve arquivo com versão de outra branch. Use 'git diff <branch> -- <file>' para comparar primeiro. AGUARDE o usuário autorizar."

# git restore (várias formas)
echo "$COMMAND" | grep -qE "git\s+restore\s+--staged" && block "CUIDADO: git restore --staged remove do stage. Use 'git diff --staged' para revisar antes. AGUARDE o usuário confirmar."
echo "$COMMAND" | grep -qE "git\s+restore\s+--source" && block "PERDA DE DADOS: git restore --source sobrescreve com versão antiga. AGUARDE o usuário autorizar."
echo "$COMMAND" | grep -qE "git\s+restore\s+[^-]" && block "PERDA DE DADOS: git restore descarta mudanças permanentemente. Use 'git stash' para salvar. AGUARDE o usuário autorizar."

# git clean
echo "$COMMAND" | grep -qE "git\s+clean\s+-[fd]" && block "PERDA DE DADOS: git clean remove arquivos não rastreados permanentemente. Liste com 'git clean -n' primeiro. AGUARDE o usuário autorizar."

# git stash drop/clear
echo "$COMMAND" | grep -qE "git\s+stash\s+(drop|clear)" && block "PERDA DE DADOS: git stash drop/clear remove stash permanentemente. Use 'git stash list' para revisar. AGUARDE o usuário autorizar."

# git reset (não só --hard)
echo "$COMMAND" | grep -qE "git\s+reset\s+--hard" && block "PERDA DE DADOS: git reset --hard descarta TODAS as mudanças. Use 'git stash' primeiro. AGUARDE o usuário autorizar."
echo "$COMMAND" | grep -qE "git\s+reset\s+HEAD~" && block "CUIDADO: git reset HEAD~ desfaz commits. Mudanças ficam unstaged mas podem ser perdidas. AGUARDE o usuário autorizar."

# git revert --no-commit (pode causar conflitos destrutivos)
echo "$COMMAND" | grep -qE "git\s+revert\s+--no-commit" && block "CUIDADO: git revert --no-commit modifica arquivos sem commit. Verifique mudanças pendentes primeiro. AGUARDE o usuário autorizar."

# =============================================================================
# APPLY DENY FROM settings.json (enforce even in skip-permissions mode)
# =============================================================================
SETTINGS_FILE=""
if [[ -f "$PWD/.claude/settings.json" ]]; then
  SETTINGS_FILE="$PWD/.claude/settings.json"
elif [[ -n "$CWT_ROOT" && -f "$CWT_ROOT/.claude/settings.json" ]]; then
  SETTINGS_FILE="$CWT_ROOT/.claude/settings.json"
fi

if [[ -n "$SETTINGS_FILE" && -f "$SETTINGS_FILE" ]]; then
  # Read deny patterns like "Bash(git push:*)" and convert to regex
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == "null" ]] && continue
    # Extract command from "Bash(command:*)" format
    if [[ "$pattern" =~ ^Bash\(([^:]+) ]]; then
      cmd_pattern="${BASH_REMATCH[1]}"
      # Convert to regex (escape special chars, replace * with .*)
      cmd_regex=$(echo "$cmd_pattern" | sed 's/[.[\*^$]/\\&/g' | sed 's/\\\*/.*/')
      if echo "$COMMAND" | grep -qE "^$cmd_regex|\\s$cmd_regex"; then
        block "settings.json deny: $cmd_pattern"
      fi
    fi
  done < <(jq -r '.permissions.deny // [] | .[]' "$SETTINGS_FILE" 2>/dev/null)
fi

# =============================================================================
# CHECK SESSION BLOCKS (restrições temporárias adicionais)
# =============================================================================
# Nota: expiração já verificada no início do script
if [[ -f "$OVERRIDES_FILE" ]]; then
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == "null" ]] && continue
    if echo "$COMMAND" | grep -qE "$pattern"; then
      TASK=$(jq -r '.task // "sessão"' "$OVERRIDES_FILE" 2>/dev/null)
      block "Override de sessão ($TASK): $pattern"
    fi
  done < <(jq -r '.overrides.block // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)

  # ===========================================================================
  # CHECK AUTO-APPROVE (responde "ask" automaticamente via tmux)
  # ===========================================================================
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
          tmux send-keys -t "$TMUX_PANE" "y" 2>/dev/null
          sleep 0.1
          tmux send-keys -t "$TMUX_PANE" "" C-m 2>/dev/null
        ) &
        disown 2>/dev/null
      fi
      # Sair do loop, já encontrou match
      break
    fi
  done < <(jq -r '.overrides.auto_approve // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)
fi

# Permitir comando (continua para handling nativo do Claude)
exit 0
