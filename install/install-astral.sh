#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Installing Astral Python Development Tools (uv & ruff)..."

if [ "$OS" = "Darwin" ]; then
    ensure_homebrew
    brew install uv ruff

elif [ "$OS" = "Linux" ]; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    log "Installing ruff..."
    curl -LsSf https://astral.sh/ruff/install.sh | sh
fi

success "Astral Python tools (uv & ruff) installed successfully!"
