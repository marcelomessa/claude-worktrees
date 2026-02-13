#!/bin/bash
# =============================================================================
# BASH-VALIDATOR - PreToolUse hook for command validation
# =============================================================================
#
# This hook is the protection layer when Claude runs with
# --dangerously-skip-permissions (CWT default mode).
#
# Features:
# 1. WORKER RESTRICTIONS: Blocks dangerous commands for workers
# 2. SESSION OVERRIDES: Allows temporary blocks/approvals
#
# Exit codes:
#   0 - Allow command
#   2 - Block (stderr shown to Claude)
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
# DETECT COORDINATOR (fallback when CLAUDE_WORKER_ID is not set)
# =============================================================================
if [[ -z "$WORKER_ID" && -n "$CWT_ROOT" && -f "$CWT_ROOT/.cwt/config.json" ]]; then
  COORD_DIR=$(jq -r '.coordinator // empty' "$CWT_ROOT/.cwt/config.json" 2>/dev/null)
  if [[ -n "$COORD_DIR" && "$COORD_DIR" != "null" ]]; then
    # Check if we are in the coordinator directory
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
# SESSION ALLOW (bypasses all restrictions - check FIRST)
# =============================================================================
if [[ -f "$OVERRIDES_FILE" ]]; then
  # Check expiration first
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
        # Command explicitly allowed - bypass all checks
        exit 0
      fi
    done < <(jq -r '.overrides.allow // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)
  fi
fi

# =============================================================================
# WORKER RESTRICTIONS (when skip-permissions is active)
# =============================================================================
if [[ "$WORKER_ID" != "coordinator" && -n "$WORKER_ID" ]]; then

  # Git: push, merge, rebase, checkout protected branches
  echo "$COMMAND" | grep -qE "git\s+push" && block "git push - coordinator only"
  echo "$COMMAND" | grep -qE "git\s+merge" && block "git merge - coordinator only"
  echo "$COMMAND" | grep -qE "git\s+rebase" && block "git rebase - coordinator only"
  echo "$COMMAND" | grep -qE "git\s+checkout\s+(main|master|dev|develop)\b" && block "checkout protected branch - coordinator only"
  # git reset --hard now blocked in UNIVERSAL section for everyone

  # Azion CLI
  echo "$COMMAND" | grep -qE "azion\s+(deploy|delete|create|update|link|unlink)" && block "azion CLI - coordinator only"

  # Process control
  echo "$COMMAND" | grep -qE "\b(kill|pkill|killall)\b" && block "kill process - coordinator only"

fi

# =============================================================================
# UNIVERSAL RESTRICTIONS (everyone, including coordinator)
# =============================================================================
echo "$COMMAND" | grep -qE "rm\s+-rf\s+(/|~|\*)" && block "dangerous rm -rf"
echo "$COMMAND" | grep -qE ">\s*/dev/sd" && block "write to disk device"
echo "$COMMAND" | grep -qE "mkfs\." && block "mkfs forbidden"
echo "$COMMAND" | grep -qE "dd\s+if=.*of=/dev" && block "dd to device"
echo "$COMMAND" | grep -qE "git\s+add\s+(-A|--all|\s\.(\s|$))" && block "git add -A/. - use specific files"

# =============================================================================
# GIT DESTRUCTIVE COMMANDS - IRREVERSIBLE DATA LOSS
# =============================================================================
# These commands can cause permanent loss of uncommitted code.
# ALL are blocked - user must explicitly authorize.

# Pattern: git checkout -- <file>
echo "$COMMAND" | grep -qE "git\s+checkout\s+--\s" && block "DATA LOSS: git checkout -- discards changes permanently. Use 'git stash' to save, or 'git commit' to preserve. WAIT for user authorization."

# Pattern: git checkout .
echo "$COMMAND" | grep -qE "git\s+checkout\s+\.\s*$" && block "DATA LOSS: git checkout . discards ALL changes. Use 'git stash' or 'git commit' first. WAIT for user authorization."

# Pattern: git checkout <hash> -- <file> (recovers old version, LOSES current!)
echo "$COMMAND" | grep -qE "git\s+checkout\s+[a-f0-9]+\s+--" && block "DATA LOSS: git checkout <commit> -- <file> overwrites current file with old version. Uncommitted changes will be LOST. Use 'git stash' first, or 'git show <commit>:<file>' to just view. WAIT for user authorization."

# Pattern: git checkout HEAD~N (goes back commits, may lose work)
echo "$COMMAND" | grep -qE "git\s+checkout\s+HEAD~" && block "DATA LOSS: git checkout HEAD~ may discard changes. Use 'git stash' first. WAIT for user authorization."

# Pattern: git checkout <branch> -- <file> (overwrites with version from another branch)
echo "$COMMAND" | grep -qE "git\s+checkout\s+\w+\s+--\s" && block "DATA LOSS: git checkout <branch> -- <file> overwrites file with version from another branch. Use 'git diff <branch> -- <file>' to compare first. WAIT for user authorization."

# git restore (various forms)
echo "$COMMAND" | grep -qE "git\s+restore\s+--staged" && block "CAUTION: git restore --staged removes from stage. Use 'git diff --staged' to review first. WAIT for user confirmation."
echo "$COMMAND" | grep -qE "git\s+restore\s+--source" && block "DATA LOSS: git restore --source overwrites with old version. WAIT for user authorization."
echo "$COMMAND" | grep -qE "git\s+restore\s+[^-]" && block "DATA LOSS: git restore discards changes permanently. Use 'git stash' to save. WAIT for user authorization."

# git clean
echo "$COMMAND" | grep -qE "git\s+clean\s+-[fd]" && block "DATA LOSS: git clean permanently removes untracked files. List with 'git clean -n' first. WAIT for user authorization."

# git stash drop/clear
echo "$COMMAND" | grep -qE "git\s+stash\s+(drop|clear)" && block "DATA LOSS: git stash drop/clear permanently removes stash. Use 'git stash list' to review. WAIT for user authorization."

# git reset (not just --hard)
echo "$COMMAND" | grep -qE "git\s+reset\s+--hard" && block "DATA LOSS: git reset --hard discards ALL changes. Use 'git stash' first. WAIT for user authorization."
echo "$COMMAND" | grep -qE "git\s+reset\s+HEAD~" && block "CAUTION: git reset HEAD~ undoes commits. Changes become unstaged but may be lost. WAIT for user authorization."

# git revert --no-commit (may cause destructive conflicts)
echo "$COMMAND" | grep -qE "git\s+revert\s+--no-commit" && block "CAUTION: git revert --no-commit modifies files without commit. Check pending changes first. WAIT for user authorization."

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
# CHECK SESSION BLOCKS (additional temporary restrictions)
# =============================================================================
# Note: expiration already checked at the beginning of the script
if [[ -f "$OVERRIDES_FILE" ]]; then
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == "null" ]] && continue
    if echo "$COMMAND" | grep -qE "$pattern"; then
      TASK=$(jq -r '.task // "session"' "$OVERRIDES_FILE" 2>/dev/null)
      block "Session override ($TASK): $pattern"
    fi
  done < <(jq -r '.overrides.block // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)

  # ===========================================================================
  # CHECK AUTO-APPROVE (automatically responds "ask" via tmux)
  # ===========================================================================
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == "null" ]] && continue
    if echo "$COMMAND" | grep -qE "$pattern"; then
      # This command should be auto-approved
      # Spawn background process to send "y" to the ask prompt
      if [[ -n "$TMUX_PANE" ]]; then
        (
          # Wait for prompt to appear
          sleep 0.3
          # Send "y" and Enter to approve
          tmux send-keys -t "$TMUX_PANE" "y" 2>/dev/null
          sleep 0.1
          tmux send-keys -t "$TMUX_PANE" "" C-m 2>/dev/null
        ) &
        disown 2>/dev/null
      fi
      # Exit loop, already found match
      break
    fi
  done < <(jq -r '.overrides.auto_approve // [] | .[]' "$OVERRIDES_FILE" 2>/dev/null)
fi

# Allow command (continues to Claude's native handling)
exit 0
