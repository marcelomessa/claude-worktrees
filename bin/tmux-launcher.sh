#!/bin/bash
# =============================================================================
# TMUX LAUNCHER - Multi-Agent Claude Environment with Tmux
# =============================================================================
# Creates tmux session with multiple windows for Claude workers
# Supports project structure with .cwt/ or legacy mode (git worktrees)
#
# Uso: ./tmux-launcher.sh [--continue|-c] [--strict] [workspace1] [workspace2] ...
#   --continue, -c  Resume previous Claude sessions in each worker
#   --strict        Use Claude's native permissions (no --dangerously-skip-permissions)
# =============================================================================

# Parse arguments (preserve exported values from cwt)
CONTINUE_FLAG="${CONTINUE_FLAG:-}"
SKIP_PERMISSIONS="${SKIP_PERMISSIONS:-1}"  # Default: skip permissions, use bash-validator
CWT_SESSION_NAME="${CWT_SESSION_NAME:-}"   # CWT session name (to group Claude sessions)
WORKSPACES_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --continue|-c)
      CONTINUE_FLAG="--continue"
      shift
      ;;
    --resume|-r)
      CONTINUE_FLAG="--resume"
      shift
      ;;
    --strict)
      SKIP_PERMISSIONS=""  # Use Claude's native permissions
      shift
      ;;
    --session|-n)
      CWT_SESSION_NAME="$2"
      shift 2
      ;;
    *)
      WORKSPACES_ARGS+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters (workspaces only)
set -- "${WORKSPACES_ARGS[@]}"

# =============================================================================
# SESSION MANAGEMENT - Groups Claude sessions from all worktrees
# =============================================================================

generate_uuid() {
  # Generate UUID v4
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    # Fallback using /dev/urandom
    od -x /dev/urandom | head -1 | awk '{print $2$3"-"$4"-4"substr($5,2)"-"substr($6,1,1)"0"substr($6,2)"-"$7$8$9}'
  fi
}

# Sessions file
get_sessions_dir() {
  local project_root="$1"
  echo "$project_root/.cwt/sessions"
}

# Save session with UUIDs from all worktrees
save_cwt_session() {
  local sessions_dir=$(get_sessions_dir "$PROJECT_ROOT")
  local session_file="$sessions_dir/${CWT_SESSION_NAME}.json"

  mkdir -p "$sessions_dir"

  # Create JSON with session IDs
  echo "{" > "$session_file"
  echo "  \"name\": \"$CWT_SESSION_NAME\"," >> "$session_file"
  echo "  \"created\": \"$(date -Iseconds)\"," >> "$session_file"
  echo "  \"sessions\": {" >> "$session_file"

  local first=true
  while IFS='=' read -r worker_id session_id; do
    [[ -z "$worker_id" ]] && continue
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo "," >> "$session_file"
    fi
    printf "    \"%s\": \"%s\"" "$worker_id" "$session_id" >> "$session_file"
  done < "$SESSION_IDS_FILE"

  echo "" >> "$session_file"
  echo "  }" >> "$session_file"
  echo "}" >> "$session_file"

  echo "💾 Session '$CWT_SESSION_NAME' saved to $session_file"
}

# Load existing session
load_cwt_session() {
  local sessions_dir=$(get_sessions_dir "$PROJECT_ROOT")
  local session_file="$sessions_dir/${CWT_SESSION_NAME}.json"

  if [[ ! -f "$session_file" ]]; then
    echo "❌ Session '$CWT_SESSION_NAME' not found"
    echo "   Available sessions:"
    ls -1 "$sessions_dir"/*.json 2>/dev/null | xargs -I{} basename {} .json | sed 's/^/     /'
    return 1
  fi

  # Load session IDs from JSON to temporary file
  while IFS=': ' read -r key value; do
    key=$(echo "$key" | tr -d '"' | xargs)
    value=$(echo "$value" | tr -d '",\n' | xargs)
    [[ -n "$key" && -n "$value" && "$key" != "name" && "$key" != "created" && "$key" != "{" && "$key" != "}" && "$key" != "sessions" ]] && \
      set_session_id "$key" "$value"
  done < <(cat "$session_file")

  echo "📂 Session '$CWT_SESSION_NAME' loaded"
  return 0
}

# Get or generate session ID for a worktree
get_session_id() {
  local worker_id="$1"
  local existing_id=$(get_session_id_value "$worker_id")

  if [[ -n "$existing_id" ]]; then
    echo "$existing_id"
  else
    local new_id=$(generate_uuid)
    set_session_id "$worker_id" "$new_id"
    echo "$new_id"
  fi
}

# Temporary file for session IDs (bash 3 compatible)
SESSION_IDS_FILE="/tmp/cwt-session-ids-$$.txt"
touch "$SESSION_IDS_FILE"

# Functions to manage session IDs without associative arrays
set_session_id() {
  local key="$1"
  local value="$2"
  # Remove existing entry and add new one
  grep -v "^$key=" "$SESSION_IDS_FILE" > "$SESSION_IDS_FILE.tmp" 2>/dev/null || true
  mv "$SESSION_IDS_FILE.tmp" "$SESSION_IDS_FILE"
  echo "$key=$value" >> "$SESSION_IDS_FILE"
}

get_session_id_value() {
  local key="$1"
  grep "^$key=" "$SESSION_IDS_FILE" 2>/dev/null | cut -d= -f2 | head -1
}

list_session_ids() {
  cat "$SESSION_IDS_FILE" 2>/dev/null
}

# Use session from environment or default
SESSION_NAME="${SESSION_NAME:-cwt}"
PULSER_INTERVAL=${PULSER_INTERVAL:-120}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
# LOG_DIR will be defined after detecting PROJECT_ROOT
CWT_BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
CWT_CONFIG_DIR="$(cd "$CWT_BIN_DIR/../config" && pwd)"
CWT_TEMPLATES_DIR="$(cd "$CWT_BIN_DIR/../templates" && pwd)"
TMUX_CONF="$CWT_CONFIG_DIR/tmux.conf"

# Detect if we are in project mode (.cwt/) or legacy mode (git worktrees)
PROJECT_ROOT="${CWT_PROJECT_ROOT:-}"
PROJECT_MODE="legacy"

if [[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT/.cwt" ]]; then
  PROJECT_MODE="project"
  PROJECT_DIR="$PROJECT_ROOT"
  STATE_FILE="$PROJECT_ROOT/.cwt/state.json"
  WORKSPACES_FILE="$PROJECT_ROOT/.cwt/workers.txt"
  LOG_DIR="${CWT_LOG_DIR:-$PROJECT_ROOT/.cwt/logs}"
  CWT_STATE_DIR="$PROJECT_ROOT/.cwt"
else
  PROJECT_DIR="${CWT_PROJECT:-$(pwd)}"
  STATE_FILE="/tmp/claude-wt-state.json"
  WORKSPACES_FILE="/tmp/cwt-workers-list.txt"
  LOG_DIR="${CWT_LOG_DIR:-/tmp/cwt-logs}"

  # Legacy mode needs a git repo to coordinate. Without .cwt/ AND without git
  # there is no project at all - bail out instead of resolving paths against an
  # empty $PROJECT_ROOT (which would target the filesystem root).
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "❌ '$PROJECT_DIR' is neither a CWT project nor a git repository."
    echo ""
    echo "   Run 'cwt init' here to initialize a CWT project,"
    echo "   or cd into a git repository first."
    exit 1
  fi

  # State lives outside the repo in legacy mode: keyed by path so that two
  # legacy repos never share a socket or a pid file.
  CWT_STATE_DIR="${TMPDIR:-/tmp}/cwt-legacy-$(printf '%s' "$PROJECT_DIR" | shasum | cut -c1-8)"
fi

# ============================================================================
# DETECTION FUNCTIONS - PROJECT MODE
# ============================================================================

# Detect coordinator directory
detect_coordinator_dir() {
  # 1. Configured in .cwt/config.json
  if [[ -f "$PROJECT_ROOT/.cwt/config.json" ]]; then
    local coord=$(jq -r '.coordinator // empty' "$PROJECT_ROOT/.cwt/config.json" 2>/dev/null)
    if [[ -n "$coord" && "$coord" != "null" ]]; then
      # Case 1: coordinator is a subdirectory (project structure)
      if [[ -d "$PROJECT_ROOT/$coord" ]]; then
        echo "$coord"
        return
      fi
      # Case 2: PROJECT_ROOT IS the coordinator (cwt init inside the repo)
      if [[ "$(basename "$PROJECT_ROOT")" == "$coord" && -d "$PROJECT_ROOT/.git" ]]; then
        echo "."
        return
      fi
    fi
  fi

  # 2. PROJECT_ROOT is a git repo (cwt init inside the repo)
  if [[ -d "$PROJECT_ROOT/.git" ]]; then
    echo "."
    return
  fi

  # 3. First folder with full .git/ (repo, not worktree)
  for dir in "$PROJECT_ROOT"/*/; do
    local name=$(basename "$dir")
    [[ "$name" == ".cwt" ]] && continue
    # .git/ as directory = main repo
    if [[ -d "$dir/.git" ]]; then
      echo "$name"
      return
    fi
  done
}

# Detect workers (ONLY coordinator worktrees, not other repos)
detect_workers_project() {
  local coord_dir=$(detect_coordinator_dir)
  local coord_path="$PROJECT_ROOT/$coord_dir"

  # If there's no coordinator, there are no workers
  [[ -z "$coord_dir" || ! -d "$coord_path" ]] && return

  # Determine search area for worktrees
  local search_area="$PROJECT_ROOT"
  # If PROJECT_ROOT is the repo itself, worktrees are in the parent
  if [[ -d "$PROJECT_ROOT/.git" ]]; then
    search_area=$(dirname "$PROJECT_ROOT")
  fi

  # List coordinator worktrees
  git -C "$coord_path" worktree list --porcelain 2>/dev/null | grep "^worktree " | cut -d' ' -f2- | while read -r wt_path; do
    # Skip the coordinator itself
    [[ "$wt_path" == "$coord_path" ]] && continue

    # Check if it's in the search area
    if [[ "$wt_path" == "$search_area"/* ]]; then
      basename "$wt_path"
    fi
  done
}

# ============================================================================
# DETECTION FUNCTIONS - LEGACY MODE (git worktrees)
# ============================================================================

detect_workers_legacy() {
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
    echo "Error: Not in a git repository" >&2
    return 1
  fi

  local main_wt=$(git -C "$PROJECT_DIR" worktree list --porcelain | head -1 | cut -d' ' -f2-)

  git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2- | while read -r wt; do
    if [[ "$wt" != "$main_wt" && -n "$wt" ]]; then
      basename "$wt" | sed 's/^workspace-//'
    fi
  done
}

# ============================================================================
# TEMPLATE SETUP AND INITIAL PROMPTS
# ============================================================================

# Install CLAUDE.md if it doesn't exist
install_claude_md() {
  local target_dir="$1"
  local role="$2"  # "coordinator" or "worker"
  local worker_id="$3"

  # If CLAUDE.md already exists, don't overwrite
  [[ -f "$target_dir/CLAUDE.md" ]] && return 0

  local template=""
  if [[ "$role" == "coordinator" ]]; then
    template="$CWT_TEMPLATES_DIR/CLAUDE.coord.md"
  else
    template="$CWT_TEMPLATES_DIR/CLAUDE.worker.md"
  fi

  if [[ -f "$template" ]]; then
    # Copy and replace WORKER_ID
    sed "s/WORKER_ID/$worker_id/g" "$template" > "$target_dir/CLAUDE.md"
    echo "   📄 CLAUDE.md instalado em $target_dir"
  fi
}

# Install settings.json with permissions and MCP config
install_settings() {
  local target_dir="$1"
  local role="$2"  # "coordinator" or "worker"
  local worker_id="$3"
  local project_root="$4"

  local claude_dir="$target_dir/.claude"
  local settings_file="$claude_dir/settings.json"

  # Create .claude directory if it doesn't exist
  mkdir -p "$claude_dir"

  # If it already exists, don't overwrite
  [[ -f "$settings_file" ]] && return 0

  # Choose template
  local template=""
  if [[ "$role" == "coordinator" ]]; then
    template="$CWT_TEMPLATES_DIR/settings.coord.json"
  else
    template="$CWT_TEMPLATES_DIR/settings.worker.json"
  fi

  if [[ -f "$template" ]]; then
    # Replace placeholders:
    # - WORKER_NAME -> worker_id
    # - CWT_ROOT_PLACEHOLDER -> project_root (real path)
    # - ~ -> $HOME (expand to absolute path)
    local install_dir="$HOME/.claude-worktrees"
    sed -e "s/WORKER_NAME/$worker_id/g" \
        -e "s|CWT_ROOT_PLACEHOLDER|$project_root|g" \
        -e "s|~/.claude-worktrees|$install_dir|g" \
        "$template" > "$settings_file"
    echo "   ⚙️  settings.json installed"
  else
    echo "   ⚠️  Template not found: $template"
  fi
}

# Install skills
install_skills() {
  local target_dir="$1"
  local role="$2"  # "coordinator" or "worker"

  local claude_dir="$target_dir/.claude"
  local skills_dir="$claude_dir/skills"
  local install_dir="$HOME/.claude-worktrees"

  # If there are no skills in install, skip
  [[ ! -d "$install_dir/templates/skills" ]] && return 0

  mkdir -p "$skills_dir"

  # Copy relevant skills
  local skills_to_copy=("cwt-kb" "cwt-budget")
  if [[ "$role" == "coordinator" ]]; then
    skills_to_copy+=("cwt-coordinator")
  else
    skills_to_copy+=("cwt-worker")
  fi

  for skill in "${skills_to_copy[@]}"; do
    if [[ -d "$install_dir/templates/skills/$skill" && ! -d "$skills_dir/$skill" ]]; then
      cp -r "$install_dir/templates/skills/$skill" "$skills_dir/"
    fi
  done
}

# Generate initial prompt for the coordinator
get_coordinator_prompt() {
  local workers_list="$1"
  cat << EOF
You are the COORDINATOR of a multi-Claude team.

CRITICAL: You COORDINATE, you do NOT implement. DELEGATE tasks to workers!

Available workers: $workers_list

Commands:
- wt-task <worker> "task" - Send task to worker
- wt-msg check - Check for messages
- wt-msg read - Read messages from workers
- tmux capture-pane -t 1 -p | tail -20 - See what worker 1 is doing

Workflow:
1. Receive request from user
2. Break into worker tasks
3. Send via wt-task
4. Monitor via wt-msg and tmux capture-pane
5. Integrate when ready

Waiting for instructions.
EOF
}

# Generate reminder prompt for coordinator (--continue)
get_coordinator_continue_prompt() {
  local workers_list="$1"
  cat << EOF
[SESSION RESUMED] You are the COORDINATOR.

Workers: $workers_list

FIRST: Check messages and worker status:
  wt-msg check && wt-msg read
  wt-msg status
EOF
}

# Generate prompt for SOLO mode (coordinator does everything)
get_solo_prompt() {
  cat << EOF
SOLO MODE - You are working alone (no workers).

You can implement directly. No need to delegate.

Waiting for instructions.
EOF
}

# Generate prompt for SOLO mode with continue
get_solo_continue_prompt() {
  cat << EOF
[SESSION RESUMED] SOLO MODE - working alone.

Continue your work.
EOF
}

# Generate initial prompt for worker
get_worker_prompt() {
  local worker_id="$1"
  cat << EOF
You are worker [$worker_id].

Check for tasks:
  wt-msg check
  wt-msg read

When done with a task:
  wt-msg send coordinator "task X completed"

Waiting for tasks from coordinator...
EOF
}

# Generate reminder prompt for worker (--continue)
get_worker_continue_prompt() {
  local worker_id="$1"
  cat << EOF
[SESSION RESUMED] You are worker [$worker_id].

Check messages: wt-msg check && wt-msg read
EOF
}

# ============================================================================
# WAIT FUNCTIONS
# ============================================================================

# Wait for Claude to be ready (detect ">" prompt)
wait_for_claude() {
  local session="$1"
  local window="$2"
  local max_attempts="${3:-90}"  # 90 attempts = ~45 seconds
  local attempt=0
  local saw_loading=0

  while [[ $attempt -lt $max_attempts ]]; do
    # Capture last lines from pane
    local output=$(tmux capture-pane -t "$session:$window" -p -S -10 2>/dev/null)

    # Claude ready: shows "❯" prompt or "bypass permissions" or ">"
    if echo "$output" | grep -qE "(^>|❯|bypass permissions)" 2>/dev/null; then
      return 0  # Claude ready for input
    fi

    # If Claude is loading, mark and keep waiting
    if echo "$output" | grep -qE "(Loading|Resuming|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏)" 2>/dev/null; then
      saw_loading=1
    fi

    # If returned to shell (% prompt) after showing Claude signs, it failed
    if echo "$output" | grep -qE "^[^>]*%[[:space:]]*$" 2>/dev/null; then
      if [[ $saw_loading -eq 1 ]] || echo "$output" | grep -qE "(No conversation|Error|failed)" 2>/dev/null; then
        return 1  # Claude failed
      fi
    fi

    sleep 0.5
    ((attempt++))
  done

  return 1  # Timeout
}

# ============================================================================
# INITIALIZATION
# ============================================================================

echo "═══════════════════════════════════════════════════════════════"
echo " 🖥️  Claude Multi-Agent Tmux Environment"
echo "═══════════════════════════════════════════════════════════════"
echo " Mode: $PROJECT_MODE"
echo " Session: $SESSION_NAME"
[[ -n "$CONTINUE_FLAG" ]] && echo " Resume: enabled (--continue)"
[[ -n "$SOLO_MODE" ]] && echo " Mode: SOLO (coordinator only)"
[[ -n "$STRICT_MODE" ]] && echo " Mode: STRICT (coordinator read-only)"

# Determine workers
if [[ -n "$SOLO_MODE" ]]; then
  # Solo mode: no workers
  WORKSPACES=()
  echo ""
  echo "🎯 SOLO mode: working with coordinator only"
elif [[ $# -gt 0 ]]; then
  WORKSPACES=("$@")
elif [[ "$PROJECT_MODE" == "project" ]]; then
  # Alternative compatible with bash 3.x (macOS default)
  WORKSPACES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && WORKSPACES+=("$line")
  done < <(detect_workers_project)
else
  WORKSPACES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && WORKSPACES+=("$line")
  done < <(detect_workers_legacy)
fi

if [[ ${#WORKSPACES[@]} -eq 0 && -z "$SOLO_MODE" ]]; then
  echo ""
  echo "ℹ️  No workers found - starting with coordinator only"
  echo "   To create workers later: wt-init worker1 worker2"
fi

# Determine coordinator directory
if [[ "$PROJECT_MODE" == "project" ]]; then
  COORD_DIR_NAME=$(detect_coordinator_dir)
  COORD_DIR="$PROJECT_ROOT/$COORD_DIR_NAME"
  if [[ ! -d "$COORD_DIR" ]]; then
    echo "⚠️  Coordinator directory not found: $COORD_DIR_NAME"
    echo "   Clone the main repo: git clone <url> main"
    exit 1
  fi
else
  COORD_DIR=$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2-)
  if [[ -z "$COORD_DIR" || ! -d "$COORD_DIR" ]]; then
    echo "❌ Coordinator not detected in $PROJECT_DIR"
    echo "   'git worktree list' returned nothing usable."
    exit 1
  fi
  COORD_DIR_NAME=$(basename "$COORD_DIR")
fi

echo " Coordinator: $COORD_DIR_NAME"
echo " Workers: ${WORKSPACES[*]}"
echo " State: $STATE_FILE"
echo " Mouse scroll: enabled"
echo "═══════════════════════════════════════════════════════════════"

# ==========================================================================
# BRANCH CHECK ON STARTUP
# ==========================================================================
WT_BRANCH="$CWT_BIN_DIR/../lib/wt-branch"
if [[ -x "$WT_BRANCH" ]]; then
  echo ""
  "$WT_BRANCH" check
  echo ""
fi

# Check if session already exists
if tmux has-session -t "=$SESSION_NAME" 2>/dev/null; then
  echo "⚠️  Session '$SESSION_NAME' already exists."
  echo "   Use: tmux attach -t =$SESSION_NAME  (to reconnect)"
  echo "   Use: tmux kill-session -t =$SESSION_NAME  (to kill)"
  exit 1
fi

# Save workspaces list
mkdir -p "$(dirname "$WORKSPACES_FILE")"
printf '%s\n' "${WORKSPACES[@]}" > "$WORKSPACES_FILE"

# Initialize state if needed
if [[ ! -f "$STATE_FILE" ]]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  echo '{"workers":{},"messages":[]}' > "$STATE_FILE"
fi

# Create log directory
mkdir -p "$LOG_DIR"
echo "📝 Logs: $LOG_DIR/cwt-*-$TIMESTAMP.log"

# Create history directory (isolates HISTFILE per worker)
mkdir -p "$CWT_STATE_DIR/history"

# ============================================================================
# START COMMUNICATION DAEMON
# ============================================================================

CWT_DAEMON_DIR="$(cd "$CWT_BIN_DIR/../daemon" && pwd)"
DAEMON_LOG="$LOG_DIR/cwt-daemon-$TIMESTAMP.log"
DAEMON_PID_FILE="$CWT_STATE_DIR/daemon.pid"
CWT_SOCKET="$CWT_STATE_DIR/cwt.sock"

# Stop previous daemon if it exists
if [[ -f "$DAEMON_PID_FILE" ]]; then
  OLD_PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "🔄 Stopping previous daemon (PID: $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null
    sleep 1
  fi
  rm -f "$DAEMON_PID_FILE"
fi

# Remove old socket
rm -f "$CWT_SOCKET"

# Start daemon
if [[ -f "$CWT_DAEMON_DIR/index.js" ]] && command -v node &>/dev/null; then
  echo "🚀 Starting communication daemon..."
  CWT_STATE_DIR="$CWT_STATE_DIR" nohup node "$CWT_DAEMON_DIR/index.js" "${PROJECT_ROOT:-$PROJECT_DIR}" > "$DAEMON_LOG" 2>&1 &
  DAEMON_PID=$!
  sleep 1

  # Check if it started correctly
  if kill -0 "$DAEMON_PID" 2>/dev/null && [[ -S "$CWT_SOCKET" ]]; then
    echo "   ✅ Daemon running (PID: $DAEMON_PID)"
    echo "   📡 Socket: $CWT_SOCKET"
  else
    echo "   ⚠️  Daemon may not have started correctly"
    echo "   📄 Log: $DAEMON_LOG"
  fi
else
  echo "⚠️  Daemon not available (node not found or daemon/index.js missing)"
  echo "   Real-time communication disabled"
fi

# Export variables for workers
export CWT_SOCKET
export CWT_PROJECT_ROOT="$PROJECT_ROOT"

# ============================================================================
# CREATE TMUX SESSION
# ============================================================================

echo "📺 Creating tmux session..."
if [[ -f "$TMUX_CONF" ]]; then
  tmux -f "$TMUX_CONF" new-session -d -s "$SESSION_NAME" -n "coordinator"
else
  tmux new-session -d -s "$SESSION_NAME" -n "coordinator"
fi
sleep 0.3

# Stamp the owning project on the session so that another project which maps to
# the same session name refuses to attach instead of hijacking this one.
# NB: set-option does not accept the "=" exact-match prefix that has-session
# takes; plain -t already prefers an exact name match over a prefix one.
tmux set-option -t "$SESSION_NAME" @cwt_root "${PROJECT_ROOT:-$PROJECT_DIR}" 2>/dev/null

# Enable logging for coordinator
tmux pipe-pane -t "$SESSION_NAME:0" -o "cat >> '$LOG_DIR/cwt-coordinator-$TIMESTAMP.log'"

# Check coordinator branch
CURRENT_BRANCH=$(git -C "$COORD_DIR" branch --show-current 2>/dev/null || echo 'unknown')

echo ""
echo "📋 Layout:"
echo "   0: coordinator ($COORD_DIR_NAME) - $CURRENT_BRANCH"

# Window 0: Coordinator
echo "🎯 Configuring coordinator..."

# Install CLAUDE.md, settings.json and skills
install_claude_md "$COORD_DIR" "coordinator" "coordinator"
install_settings "$COORD_DIR" "coordinator" "coordinator" "$PROJECT_ROOT"
install_skills "$COORD_DIR" "coordinator"

tmux send-keys -t "$SESSION_NAME:0" "export CLAUDE_WORKER_ID='coordinator'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "export CWT_PROJECT_ROOT='$PROJECT_ROOT'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "export CWT_SOCKET='$CWT_SOCKET'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "export HISTFILE='$PROJECT_ROOT/.cwt/history/coordinator.history'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "cd '$COORD_DIR'" Enter
sleep 0.2
tmux send-keys -t "$SESSION_NAME:0" "echo '🎯 COORDINATOR - $COORD_DIR_NAME ($CURRENT_BRANCH)'" Enter
sleep 0.2
# Determine Claude flags
CLAUDE_FLAGS="${SKIP_PERMISSIONS:+--dangerously-skip-permissions}"

# Session management with UUIDs
if [[ -n "$CWT_SESSION_NAME" ]]; then
  # Load existing session if --resume
  if [[ "$CONTINUE_FLAG" == "--resume" ]]; then
    if ! load_cwt_session; then
      echo "   ⚠️  Session not found, creating new one..."
    fi
  fi

  # Get session ID for coordinator
  COORD_SESSION_ID=$(get_session_id "coordinator")
  CLAUDE_FLAGS="$CLAUDE_FLAGS --session-id $COORD_SESSION_ID"
  echo "   🔑 Session ID (coordinator): ${COORD_SESSION_ID:0:8}..."
elif [[ -n "$CONTINUE_FLAG" ]]; then
  CLAUDE_FLAGS="$CLAUDE_FLAGS --continue"
fi

tmux send-keys -t "$SESSION_NAME:0" "claude $CLAUDE_FLAGS" Enter

# Create window for each worker
WINDOW_NUM=1
WORKER_WINDOWS=()
for workspace in "${WORKSPACES[@]}"; do
  # Determine worker directory
  if [[ "$PROJECT_MODE" == "project" ]]; then
    WORKSPACE_DIR="$PROJECT_ROOT/$workspace"
  else
    # Legacy mode: search for worktree
    WORKSPACE_DIR=""
    while IFS= read -r wt; do
      wt_name=$(basename "$wt" | sed 's/^workspace-//')
      if [[ "$wt_name" == "$workspace" || "$(basename "$wt")" == "$workspace" ]]; then
        WORKSPACE_DIR="$wt"
        break
      fi
    done < <(git -C "$PROJECT_DIR" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-)

    [[ -z "$WORKSPACE_DIR" ]] && WORKSPACE_DIR="$(dirname "$COORD_DIR")/workspace-$workspace"
  fi

  if [[ ! -d "$WORKSPACE_DIR" ]]; then
    echo "   ⚠️  $WINDOW_NUM: $workspace (NOT FOUND)"
    ((WINDOW_NUM++))
    continue
  fi

  # Branch do worker
  wt_branch=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || echo '?')
  echo "   $WINDOW_NUM: $workspace - $wt_branch"

  # Install CLAUDE.md, settings.json and skills
  install_claude_md "$WORKSPACE_DIR" "worker" "$workspace"
  install_settings "$WORKSPACE_DIR" "worker" "$workspace" "$PROJECT_ROOT"
  install_skills "$WORKSPACE_DIR" "worker"

  # Create window
  tmux new-window -t "$SESSION_NAME" -n "$workspace"
  sleep 0.3

  # Logging
  tmux pipe-pane -t "$SESSION_NAME:$WINDOW_NUM" -o "cat >> '$LOG_DIR/cwt-$workspace-$TIMESTAMP.log'"

  # Configure
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CLAUDE_WORKER_ID='$workspace'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CWT_PROJECT_ROOT='$PROJECT_ROOT'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export CWT_SOCKET='$CWT_SOCKET'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "export HISTFILE='$PROJECT_ROOT/.cwt/history/$workspace.history'" Enter
  sleep 0.2
  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "cd '$WORKSPACE_DIR'" Enter
  sleep 0.2

  # Determine worker flags
  WORKER_FLAGS="${SKIP_PERMISSIONS:+--dangerously-skip-permissions}"
  if [[ -n "$CWT_SESSION_NAME" ]]; then
    WORKER_SESSION_ID=$(get_session_id "$workspace")
    WORKER_FLAGS="$WORKER_FLAGS --session-id $WORKER_SESSION_ID"
    echo "   🔑 Session ID ($workspace): ${WORKER_SESSION_ID:0:8}..."
  elif [[ -n "$CONTINUE_FLAG" ]]; then
    WORKER_FLAGS="$WORKER_FLAGS $CONTINUE_FLAG"
  fi

  tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "claude $WORKER_FLAGS" Enter

  # Save info to send prompt later
  WORKER_WINDOWS+=("$WINDOW_NUM:$workspace")

  ((WINDOW_NUM++))
done

# Send initial prompts to coordinator and workers (after all have started)
echo "⏳ Waiting for Claude to start..."

# Wait and send prompt to coordinator
echo "   ⏳ Waiting for coordinator..."
if wait_for_claude "$SESSION_NAME" 0; then
  # Choose prompt based on mode
  if [[ -n "$SOLO_MODE" ]]; then
    if [[ -n "$CONTINUE_FLAG" ]]; then
      COORD_PROMPT=$(get_solo_continue_prompt)
    else
      COORD_PROMPT=$(get_solo_prompt)
    fi
  elif [[ -n "$CONTINUE_FLAG" ]]; then
    COORD_PROMPT=$(get_coordinator_continue_prompt "${WORKSPACES[*]}")
  else
    COORD_PROMPT=$(get_coordinator_prompt "${WORKSPACES[*]}")
  fi
  tmux send-keys -t "$SESSION_NAME:0" "$COORD_PROMPT"
  sleep 0.1
  tmux send-keys -t "$SESSION_NAME:0" "" C-m
  echo "   ✅ Coordinator ready"
else
  # If --continue failed, restart without the flag
  if [[ -n "$CONTINUE_FLAG" ]]; then
    echo "   ⚠️  Coordinator: --continue failed, restarting..."
    tmux send-keys -t "$SESSION_NAME:0" "claude ${SKIP_PERMISSIONS:+--dangerously-skip-permissions}" Enter
    if wait_for_claude "$SESSION_NAME" 0; then
      if [[ -n "$SOLO_MODE" ]]; then
        COORD_PROMPT=$(get_solo_prompt)
      else
        COORD_PROMPT=$(get_coordinator_prompt "${WORKSPACES[*]}")
      fi
      tmux send-keys -t "$SESSION_NAME:0" "$COORD_PROMPT"
      sleep 0.1
      tmux send-keys -t "$SESSION_NAME:0" "" C-m
      echo "   ✅ Coordinator ready (fallback)"
    else
      echo "   ⚠️  Coordinator: Claude did not start (check window 0)"
    fi
  else
    echo "   ⚠️  Coordinator: Claude did not start (check window 0)"
  fi
fi

# Wait and send prompts to workers
for worker_info in "${WORKER_WINDOWS[@]}"; do
  win_num="${worker_info%%:*}"
  worker_id="${worker_info#*:}"
  echo "   ⏳ Waiting for $worker_id..."
  if wait_for_claude "$SESSION_NAME" "$win_num"; then
    # Always send prompt - full or summarized
    if [[ -n "$CONTINUE_FLAG" ]]; then
      WORKER_PROMPT=$(get_worker_continue_prompt "$worker_id")
    else
      WORKER_PROMPT=$(get_worker_prompt "$worker_id")
    fi
    tmux send-keys -t "$SESSION_NAME:$win_num" "$WORKER_PROMPT"
    sleep 0.1
    tmux send-keys -t "$SESSION_NAME:$win_num" "" C-m
    echo "   ✅ $worker_id ready"
  else
    # If --continue failed, restart without the flag
    if [[ -n "$CONTINUE_FLAG" ]]; then
      echo "   ⚠️  $worker_id: --continue failed, restarting..."
      tmux send-keys -t "$SESSION_NAME:$win_num" "claude ${SKIP_PERMISSIONS:+--dangerously-skip-permissions}" Enter
      if wait_for_claude "$SESSION_NAME" "$win_num"; then
        WORKER_PROMPT=$(get_worker_prompt "$worker_id")
        tmux send-keys -t "$SESSION_NAME:$win_num" "$WORKER_PROMPT"
        sleep 0.1
        tmux send-keys -t "$SESSION_NAME:$win_num" "" C-m
        echo "   ✅ $worker_id ready (fallback)"
      else
        echo "   ⚠️  $worker_id: Claude did not start (check window $win_num)"
      fi
    else
      echo "   ⚠️  $worker_id: Claude did not start (check window $win_num)"
    fi
  fi
done

# Save CWT session if using named sessions
if [[ -n "$CWT_SESSION_NAME" ]]; then
  save_cwt_session
fi

# Window final: Monitor
echo "   $WINDOW_NUM: monitor"
tmux new-window -t "$SESSION_NAME" -n "monitor"
sleep 0.2
tmux send-keys -t "$SESSION_NAME:$WINDOW_NUM" "cd '$COORD_DIR' && echo '📊 Monitor - $SESSION_NAME'" Enter

# ============================================================================
# START PULSER (activity monitor)
# ============================================================================

PULSER_SCRIPT="$CWT_BIN_DIR/tmux-pulser.sh"
PULSER_LOG="$LOG_DIR/cwt-pulser-$TIMESTAMP.log"
PULSER_PID_FILE="$PROJECT_ROOT/.cwt/pulser.pid"

# Stop previous pulser if it exists
if [[ -f "$PULSER_PID_FILE" ]]; then
  OLD_PID=$(cat "$PULSER_PID_FILE" 2>/dev/null)
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null
  fi
  rm -f "$PULSER_PID_FILE"
fi

# Start pulser in background
if [[ -f "$PULSER_SCRIPT" ]]; then
  echo ""
  echo "🔄 Starting pulser..."
  SESSION_NAME="$SESSION_NAME" CWT_PROJECT_ROOT="$PROJECT_ROOT" \
    nohup "$PULSER_SCRIPT" >> "$PULSER_LOG" 2>&1 &
  echo $! > "$PULSER_PID_FILE"
  sleep 0.3
  if kill -0 "$(cat "$PULSER_PID_FILE")" 2>/dev/null; then
    echo "   ✅ Pulser ativo (intervalo: ${PULSER_INTERVAL:-120}s)"
  fi
fi

echo ""
echo "✅ Environment created!"
echo ""
echo "📋 Tmux shortcuts (Ctrl+b is the prefix):"
echo "   Ctrl+b n    Next window"
echo "   Ctrl+b p    Previous window"
echo "   Ctrl+b 0-9  Go to window N"
echo "   Ctrl+b d    Detach"
echo ""

# Select coordinator window before connecting
tmux select-window -t "$SESSION_NAME:0"

# Connect
sleep 0.5
exec tmux attach -t "$SESSION_NAME"
