#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up Visual Studio Code Configuration (settings, keybindings, snippets)..."

# 1. Install or update VSCode application
DO_CODE=true
if command -v code &>/dev/null; then
    CODE_VER="$(code --version 2>/dev/null | head -n 1 || true)"
    ask_update_tool "VSCode" "$CODE_VER" DO_CODE
fi

if [ "$DO_CODE" = true ]; then
    log "Installing / Updating Visual Studio Code..."
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew upgrade --cask visual-studio-code 2>/dev/null || brew install --cask visual-studio-code
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            # Ubuntu / Debian official repository
            run_sudo apt-get update -y
            run_sudo apt-get install -y wget gpg apt-transport-https
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
            run_sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            rm -f /tmp/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | run_sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            run_sudo apt-get update -y
            run_sudo apt-get install -y code
        elif command -v dnf &>/dev/null; then
            # Fedora official repository
            run_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            run_sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            run_sudo dnf check-update || true
            run_sudo dnf install -y code
        fi
    fi
fi

if command -v code &>/dev/null; then
    success "VSCode is ready ($(code --version 2>/dev/null | head -n 1 || echo 'ready'))"
else
    warn "Could not install VSCode binary automatically. Proceeding with configuration symlinks..."
fi

# 2. Determine platform-specific VSCode User configuration directory
if [ "$OS" = "Darwin" ]; then
    VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
elif [ "$OS" = "Linux" ]; then
    VSCODE_USER_DIR="$HOME/.config/Code/User"
fi

mkdir -p "$VSCODE_USER_DIR"

# 3. Backup & Symlink settings.json
if [ -f "$DOTFILES_DIR/vscode/settings.json" ]; then
    if [ -f "$VSCODE_USER_DIR/settings.json" ] && [ ! -L "$VSCODE_USER_DIR/settings.json" ]; then
        log "Backing up existing VSCode settings.json to settings.json.bak..."
        cp "$VSCODE_USER_DIR/settings.json" "$VSCODE_USER_DIR/settings.json.bak"
    fi
    ln -sfn "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_USER_DIR/settings.json"
    success "Linked VSCode settings.json"
fi

# 4. Backup & Symlink keybindings.json
if [ -f "$DOTFILES_DIR/vscode/keybindings.json" ]; then
    if [ -f "$VSCODE_USER_DIR/keybindings.json" ] && [ ! -L "$VSCODE_USER_DIR/keybindings.json" ]; then
        cp "$VSCODE_USER_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json.bak"
    fi
    ln -sfn "$DOTFILES_DIR/vscode/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
    success "Linked VSCode keybindings.json"
fi

# 5. Backup & Symlink snippets directory
if [ -d "$DOTFILES_DIR/vscode/snippets" ]; then
    if [ -d "$VSCODE_USER_DIR/snippets" ] && [ ! -L "$VSCODE_USER_DIR/snippets" ]; then
        cp -r "$VSCODE_USER_DIR/snippets" "$VSCODE_USER_DIR/snippets.bak"
    fi
    ln -sfn "$DOTFILES_DIR/vscode/snippets" "$VSCODE_USER_DIR/snippets"
    success "Linked VSCode snippets directory"
fi

log "Note: VSCode extensions are managed manually via Settings Sync."

success "VSCode setup complete!"
