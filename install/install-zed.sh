#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up Zed Editor Configuration & Extensions..."

# 1. Install or update Zed application
DO_ZED=true
if command -v zed &>/dev/null || [ -d "/Applications/Zed.app" ]; then
    ZED_VER="$(zed --version 2>/dev/null | head -n 1 || echo 'installed')"
    ask_update_tool "Zed" "$ZED_VER" DO_ZED
fi

if [ "$DO_ZED" = true ]; then
    log "Installing / Updating Zed Editor..."
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew upgrade --cask zed 2>/dev/null || brew install --cask zed
    elif [ "$OS" = "Linux" ]; then
        log "Installing Zed via official curl installer..."
        curl -f https://zed.dev/install.sh | sh
    fi
fi

if command -v zed &>/dev/null || [ -d "/Applications/Zed.app" ]; then
    success "Zed Editor is ready"
else
    warn "Could not install Zed binary automatically. Proceeding with configuration symlinks..."
fi

# 2. Determine platform-specific Zed configuration directory
ZED_CONFIG_DIR="$HOME/.config/zed"
mkdir -p "$ZED_CONFIG_DIR"

# 3. Backup & Symlink settings.json
if [ -f "$DOTFILES_DIR/zed/settings.json" ]; then
    if [ -f "$ZED_CONFIG_DIR/settings.json" ] && [ ! -L "$ZED_CONFIG_DIR/settings.json" ]; then
        log "Backing up existing Zed settings.json to settings.json.bak..."
        cp "$ZED_CONFIG_DIR/settings.json" "$ZED_CONFIG_DIR/settings.json.bak"
    fi
    ln -sfn "$DOTFILES_DIR/zed/settings.json" "$ZED_CONFIG_DIR/settings.json"
    success "Linked ~/.config/zed/settings.json"
fi

# 4. Backup & Symlink keymap.json
if [ -f "$DOTFILES_DIR/zed/keymap.json" ]; then
    if [ -f "$ZED_CONFIG_DIR/keymap.json" ] && [ ! -L "$ZED_CONFIG_DIR/keymap.json" ]; then
        log "Backing up existing Zed keymap.json to keymap.json.bak..."
        cp "$ZED_CONFIG_DIR/keymap.json" "$ZED_CONFIG_DIR/keymap.json.bak"
    fi
    ln -sfn "$DOTFILES_DIR/zed/keymap.json" "$ZED_CONFIG_DIR/keymap.json"
    success "Linked ~/.config/zed/keymap.json"
fi

# 5. Link local development extensions if present (e.g. flow-icons)
if [ "$OS" = "Darwin" ]; then
    ZED_EXT_DIR="$HOME/Library/Application Support/Zed/extensions/installed"
elif [ "$OS" = "Linux" ]; then
    ZED_EXT_DIR="$HOME/.local/share/zed/extensions/installed"
fi

if [ -d "$HOME/Codes/flow-icons-zed" ]; then
    mkdir -p "$ZED_EXT_DIR"
    if [ ! -e "$ZED_EXT_DIR/flow-icons" ]; then
        ln -sfn "$HOME/Codes/flow-icons-zed" "$ZED_EXT_DIR/flow-icons"
        success "Linked local extension flow-icons -> ~/Codes/flow-icons-zed"
    fi
fi

log "Note: Zed extensions (angular, bearded-theme, html) auto-sync on launch via auto_install_extensions in settings.json."

success "Zed Editor setup complete!"
