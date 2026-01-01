#!/bin/bash
# =============================================================================
# FILE-PROTECTOR - PreToolUse hook to protect sensitive files
# =============================================================================
#
# Blocks workers from editing protected files (azion.config.*, etc.)
# Coordinator can edit these files.
#
# Exit codes:
#   0 - Allow
#   2 - Block (stderr shown to Claude)
# =============================================================================

INPUT=$(cat)

WORKER_ID="${CLAUDE_WORKER_ID:-}"

# Coordinator pode editar qualquer arquivo
[[ "$WORKER_ID" == "coordinator" ]] && exit 0

# Extrair tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Só verificar Edit e Write
[[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]] && exit 0

# Extrair file_path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Extrair apenas o nome do arquivo
FILE_NAME=$(basename "$FILE_PATH")

block() {
  echo "❌ BLOCKED: $1" >&2
  echo "   Use: wt-task coordinator \"editar $FILE_NAME\"" >&2
  exit 2
}

# =============================================================================
# PROTECTED FILES (workers cannot edit)
# =============================================================================

# azion.config.*
if [[ "$FILE_NAME" == azion.config.* ]]; then
  block "Arquivo protegido: $FILE_NAME (apenas coordinator)"
fi

# azion.json
if [[ "$FILE_NAME" == "azion.json" ]]; then
  block "Arquivo protegido: $FILE_NAME (apenas coordinator)"
fi

# .env files (segurança)
if [[ "$FILE_NAME" == .env* ]]; then
  block "Arquivo protegido: $FILE_NAME (apenas coordinator)"
fi

# Arquivos de deploy/CI
if [[ "$FILE_NAME" == ".github"* || "$FILE_NAME" == "Dockerfile"* ]]; then
  block "Arquivo protegido: $FILE_NAME (apenas coordinator)"
fi

# Allow
exit 0
