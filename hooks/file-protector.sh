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

# Locate the CWT project, if any
find_cwt_root() {
  if [[ -n "$CWT_PROJECT_ROOT" && -d "$CWT_PROJECT_ROOT/.cwt" ]]; then
    echo "$CWT_PROJECT_ROOT"
    return 0
  fi

  local dir="$PWD"
  while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    [[ -d "$dir/.cwt" ]] && { echo "$dir"; return 0; }
    dir=$(dirname "$dir")
  done
  return 1
}

# These are CWT worker restrictions, not general file safety. `cwt init` leaves
# .claude/settings.json in the project, which Claude Code loads for every
# session under it - so stay out of the way of plain, non-CWT sessions.
[[ -z "$WORKER_ID" && -z "$(find_cwt_root)" ]] && exit 0

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
