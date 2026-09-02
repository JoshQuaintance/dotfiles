#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up Mise (Polyglot Runtime & Node 24 Manager)..."

# 1. Install Mise
if ! command -v mise &>/dev/null && [ ! -f "$HOME/.local/bin/mise" ]; then
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew install mise
    elif [ "$OS" = "Linux" ]; then
        ensure_base_deps
        log "Installing mise via official installer..."
        curl -fsSL https://mise.run | sh
    fi
fi

# Ensure ~/.local/bin/mise is available in PATH
export PATH="$HOME/.local/bin:$PATH"

# 2. Symlink Mise Configuration
mkdir -p "$HOME/.config/mise"
if [ -f "$DOTFILES_DIR/mise/config.toml" ]; then
    ln -sfn "$DOTFILES_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"
    success "Linked ~/.config/mise/config.toml"
fi

# 3. Install & Set Default Node 24
if command -v mise &>/dev/null; then
    log "Installing and setting Node 24 as global default..."
    mise use -g node@24
    mise install -y
    success "Node 24 installed and set as default via mise!"
fi

success "Mise setup complete!"
