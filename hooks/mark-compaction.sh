#!/bin/bash
# =============================================================================
# MARK-COMPACTION - Creates marker file before context compaction
# =============================================================================
# Called by PreCompact hook to signal that compaction occurred.
# wt-check.sh detects this marker and alerts the agent.
# =============================================================================

# Find .cwt/ directory
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

if [[ -n "$CWT_ROOT" ]]; then
  # Create marker with timestamp
  echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$CWT_ROOT/.cwt/compacted.marker"
fi

exit 0
