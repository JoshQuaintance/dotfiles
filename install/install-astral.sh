#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up Astral Python Development Tools (uv & ruff)..."

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

DO_ASTRAL=true
if command -v uv &>/dev/null; then
    UV_VER="$(uv --version 2>/dev/null | head -n 1 || true)"
    ask_update_tool "Astral tools (uv & ruff)" "$UV_VER" DO_ASTRAL
fi

if [ "$DO_ASTRAL" = true ]; then
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew upgrade uv 2>/dev/null || brew install uv
        brew upgrade ruff 2>/dev/null || brew install ruff

    elif [ "$OS" = "Linux" ]; then
        ensure_base_deps
        log "Installing / Updating uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        log "Installing / Updating ruff..."
        curl -LsSf https://astral.sh/ruff/install.sh | sh
    fi
fi

success "Astral Python tools (uv & ruff) ready!"
