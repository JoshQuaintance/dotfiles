#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up NVM (Node Version Manager)..."

export NVM_DIR="$HOME/.nvm"
DO_NVM=true

if [ -s "$NVM_DIR/nvm.sh" ]; then
    NVM_VER="$(source "$NVM_DIR/nvm.sh" 2>/dev/null && nvm --version 2>/dev/null || echo "installed")"
    ask_update_tool "NVM" "$NVM_VER" DO_NVM
fi

if [ "$DO_NVM" = true ]; then
    if [ -d "$NVM_DIR/.git" ]; then
        log "Updating NVM via official git repository..."
        (
            cd "$NVM_DIR"
            git fetch --tags origin
            LATEST_TAG="$(git describe --tags --abbrev=0 --match "v[0-9]*" "$(git rev-list --tags --max-count=1)")"
            git checkout "$LATEST_TAG" --quiet
        )
    else
        log "Cloning NVM from official repository..."
        git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
        (
            cd "$NVM_DIR"
            LATEST_TAG="$(git describe --tags --abbrev=0 --match "v[0-9]*" "$(git rev-list --tags --max-count=1)")"
            git checkout "$LATEST_TAG" --quiet
        )
    fi
    success "NVM ready ($NVM_DIR)!"
else
    log "Keeping existing NVM."
fi
