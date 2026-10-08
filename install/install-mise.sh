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
link_dotfile "config/mise/config.toml" "$HOME/.config/mise/config.toml"

# 3. Install every runtime pinned in config/mise/config.toml (node, python, bun, uv, ruff)
if command -v mise &>/dev/null; then
    log "Installing pinned runtimes via mise..."
    mise install -y
    success "mise runtimes installed: $(mise ls --current 2>/dev/null | awk '{print $1"@"$2}' | tr '\n' ' ')"
fi

success "Mise setup complete!"
