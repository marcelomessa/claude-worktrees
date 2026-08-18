#!/bin/bash
# =============================================================================
# CLAUDE WORKTREES - Installation Script
# =============================================================================

set -e

INSTALL_DIR="${INSTALL_DIR:-$HOME/.claude-worktrees}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         Claude Worktrees - Multi-Agent Environment            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Check dependencies
echo "🔍 Checking dependencies..."
MISSING=""
command -v git >/dev/null 2>&1 || MISSING="$MISSING git"
command -v tmux >/dev/null 2>&1 || MISSING="$MISSING tmux"
command -v jq >/dev/null 2>&1 || MISSING="$MISSING jq"
command -v node >/dev/null 2>&1 || MISSING="$MISSING node"
command -v nc >/dev/null 2>&1 || MISSING="$MISSING netcat"
command -v claude >/dev/null 2>&1 || MISSING="$MISSING claude"

if [[ -n "$MISSING" ]]; then
  echo ""
  echo "⚠️  Missing dependencies:$MISSING"
  echo ""
  echo "Install with:"
  echo "  brew install tmux jq node netcat"
  echo "  npm install -g @anthropic-ai/claude-code"
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create directories
echo "📁 Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# Copy files
echo "📦 Copying files..."
cp -r "$SCRIPT_DIR/bin" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/daemon" "$INSTALL_DIR/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/config" "$INSTALL_DIR/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/hooks" "$INSTALL_DIR/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/templates" "$INSTALL_DIR/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/demo" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/" 2>/dev/null || echo "0.0.1" > "$INSTALL_DIR/VERSION"

# Make executable
chmod +x "$INSTALL_DIR/bin/"*
chmod +x "$INSTALL_DIR/lib/"*
chmod +x "$INSTALL_DIR/hooks/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/daemon/"*.js 2>/dev/null || true
chmod +x "$INSTALL_DIR/demo/"*.sh 2>/dev/null || true

# Create symlinks
echo "🔗 Creating symlinks..."
ln -sf "$INSTALL_DIR/bin/cwt" "$BIN_DIR/cwt"
ln -sf "$INSTALL_DIR/lib/wt-msg" "$BIN_DIR/wt-msg"
ln -sf "$INSTALL_DIR/lib/wt-init" "$BIN_DIR/wt-init"
ln -sf "$INSTALL_DIR/lib/wt-setup" "$BIN_DIR/wt-setup"
ln -sf "$INSTALL_DIR/lib/wt-task" "$BIN_DIR/wt-task"
ln -sf "$INSTALL_DIR/hooks/wt-sync.sh" "$BIN_DIR/wt-sync"
ln -sf "$INSTALL_DIR/hooks/wt-check.sh" "$BIN_DIR/wt-check"
ln -sf "$INSTALL_DIR/lib/wt-override" "$BIN_DIR/wt-override"
ln -sf "$INSTALL_DIR/lib/wt-billing" "$BIN_DIR/wt-billing"
ln -sf "$INSTALL_DIR/lib/wt-branch" "$BIN_DIR/wt-branch"
ln -sf "$INSTALL_DIR/lib/wt-kb" "$BIN_DIR/wt-kb"

# Sync Knowledge Base templates
echo "📚 Syncing Knowledge Base..."
GLOBAL_KB="$HOME/.cwt/knowledge"
TEMPLATES_KB="$INSTALL_DIR/templates/knowledge"

if [[ -d "$TEMPLATES_KB" ]]; then
  for category in patterns guidelines; do
    if [[ -d "$TEMPLATES_KB/$category" ]]; then
      mkdir -p "$GLOBAL_KB/$category"
      for file in "$TEMPLATES_KB/$category"/*.md; do
        [[ -f "$file" ]] || continue
        dest="$GLOBAL_KB/$category/$(basename "$file")"
        [[ -f "$dest" ]] || cp "$file" "$dest"
      done
    fi
  done
  [[ -f "$TEMPLATES_KB/index.json" && ! -f "$GLOBAL_KB/index.json" ]] && \
    cp "$TEMPLATES_KB/index.json" "$GLOBAL_KB/"
  echo "   Global KB: $GLOBAL_KB"
fi

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "⚠️  Add to your ~/.zshrc or ~/.bashrc:"
  echo ""
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
fi

# Detect shell and add alias
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
  # Match the marker we actually write, otherwise every re-run appends another
  # PATH block (the old check looked for "claude-worktrees", which never
  # matches the "# Claude Worktrees" comment).
  if ! grep -q "^# Claude Worktrees$" "$SHELL_RC"; then
    echo "" >> "$SHELL_RC"
    echo "# Claude Worktrees" >> "$SHELL_RC"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
    echo "✅ PATH added to $SHELL_RC"
  fi
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Usage:"
echo "  cwt init --repo <repo>   # Initialize project"
echo "  wt-init <workers...>     # Create worktrees"
echo "  cwt                      # Start multi-agent environment"
echo ""
echo "Communication:"
echo "  wt-msg send <worker> \"msg\"  # Send message"
echo "  wt-task <worker> \"task\"     # Send task"
echo "  wt-sync broadcast \"msg\"     # Broadcast"
echo ""
echo "Session Overrides:"
echo "  wt-override allow \"git push\" --duration 2h  # Auto-approve asks"
echo "  wt-override block \"rm -rf\"                  # Temporary block"
echo "  wt-override list                            # List overrides"
echo ""
echo "Billing (requires npx ccusage):"
echo "  wt-billing              # Current project cost"
echo "  wt-billing all          # All projects"
echo "  wt-billing total        # Total (for status bar)"
echo ""
echo "Branch sync:"
echo "  wt-branch               # Branch status"
echo "  wt-branch sync          # Fetch and status"
echo "  wt-branch check         # Quick check (for hooks)"
echo ""
echo "Knowledge Base:"
echo "  wt-kb query \"text\"      # Search patterns/guidelines"
echo "  wt-kb list              # List entries"
echo "  wt-kb discover \"...\"    # Share discovery"
echo "  wt-kb safety check X    # Check if command is safe"
echo ""
echo "Restart terminal or run:"
echo "  source $SHELL_RC"
