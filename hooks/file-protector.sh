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

# Coordinator can edit any file
[[ "$WORKER_ID" == "coordinator" ]] && exit 0

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Edit and Write
[[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]] && exit 0

# Extract file_path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Extract just the file name
FILE_NAME=$(basename "$FILE_PATH")

block() {
  echo "❌ BLOCKED: $1" >&2
  echo "   Use: wt-task coordinator \"edit $FILE_NAME\"" >&2
  exit 2
}

# =============================================================================
# PROTECTED FILES (workers cannot edit)
# =============================================================================

# azion.config.*
if [[ "$FILE_NAME" == azion.config.* ]]; then
  block "Protected file: $FILE_NAME (coordinator only)"
fi

# azion.json
if [[ "$FILE_NAME" == "azion.json" ]]; then
  block "Protected file: $FILE_NAME (coordinator only)"
fi

# .env files (security)
if [[ "$FILE_NAME" == .env* ]]; then
  block "Protected file: $FILE_NAME (coordinator only)"
fi

# Deploy/CI files
if [[ "$FILE_NAME" == ".github"* || "$FILE_NAME" == "Dockerfile"* ]]; then
  block "Protected file: $FILE_NAME (coordinator only)"
fi

# Allow
exit 0
