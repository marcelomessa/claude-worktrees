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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create directories
echo "📁 Criando diretórios..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# Copy files
echo "📦 Copiando arquivos..."
cp -r "$SCRIPT_DIR/bin" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/hooks" "$INSTALL_DIR/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/templates" "$INSTALL_DIR/" 2>/dev/null || true

# Make executable
chmod +x "$INSTALL_DIR/bin/"*
chmod +x "$INSTALL_DIR/lib/"*

# Create symlinks
echo "🔗 Criando symlinks..."
ln -sf "$INSTALL_DIR/bin/cwt" "$BIN_DIR/cwt"
ln -sf "$INSTALL_DIR/lib/wt-msg" "$BIN_DIR/wt-msg"
ln -sf "$INSTALL_DIR/lib/wt-init" "$BIN_DIR/wt-init"
ln -sf "$INSTALL_DIR/lib/wt-setup" "$BIN_DIR/wt-setup"
ln -sf "$INSTALL_DIR/lib/wt-task" "$BIN_DIR/wt-task"

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "⚠️  Adicione ao seu ~/.zshrc ou ~/.bashrc:"
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
  if ! grep -q "claude-worktrees" "$SHELL_RC"; then
    echo "" >> "$SHELL_RC"
    echo "# Claude Worktrees" >> "$SHELL_RC"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
    echo "✅ PATH adicionado ao $SHELL_RC"
  fi
fi

echo ""
echo "✅ Instalação concluída!"
echo ""
echo "Uso:"
echo "  cwt              # Iniciar ambiente interativo"
echo "  cwt --help       # Ver ajuda"
echo "  wt-msg status    # Status do worktree"
echo ""
echo "Reinicie o terminal ou execute:"
echo "  source $SHELL_RC"
