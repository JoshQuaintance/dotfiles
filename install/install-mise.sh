#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up Mise (Polyglot Runtime & Node 24 Manager)..."

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

# 1. Install or Update Mise
DO_MISE=true
if command -v mise &>/dev/null || [ -f "$HOME/.local/bin/mise" ]; then
    MISE_BIN="mise"
    [ -f "$HOME/.local/bin/mise" ] && MISE_BIN="$HOME/.local/bin/mise"
    MISE_VER="$("$MISE_BIN" --version 2>/dev/null | head -n 1 || true)"
    ask_update_tool "Mise" "$MISE_VER" DO_MISE
fi

if [ "$DO_MISE" = true ]; then
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew upgrade mise 2>/dev/null || brew install mise
    elif [ "$OS" = "Linux" ]; then
        ensure_base_deps
        log "Installing / Updating mise via official installer..."
        curl -fsSL https://mise.run | sh
    fi
fi

# 2. Symlink Mise Configuration
mkdir -p "$HOME/.config/mise"
if [ -f "$DOTFILES_DIR/mise/config.toml" ]; then
    ln -sfn "$DOTFILES_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"
    success "Linked ~/.config/mise/config.toml"
fi

# 3. Install & Set Default Node 24
if command -v mise &>/dev/null; then
    log "Configuring Node 24 via mise..."
    mise use -g node@24
    mise install -y
    success "Node 24 configured and set as default via mise!"
fi

success "Mise setup complete!"
