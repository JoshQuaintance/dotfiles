#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODE="${1:---full}"
log "Setting up Neovim (Mode: $MODE)..."

# 1. Install Neovim & Tree-sitter CLI
if [ "$OS" = "Darwin" ]; then
    ensure_homebrew
    brew install neovim tree-sitter-cli
elif [ "$OS" = "Linux" ]; then
    if command -v apt-get &>/dev/null; then
        # Ubuntu / Debian
        sudo apt-get install -y neovim curl git build-essential
    elif command -v dnf &>/dev/null; then
        # Fedora
        sudo dnf install -y neovim curl git make gcc
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm neovim tree-sitter
    fi

    # Check Neovim version; if < 0.9 on older Ubuntu, install AppImage
    if command -v nvim &>/dev/null; then
        NVIM_VER="$(nvim --version | head -n 1 | awk '{print $2}' | sed 's/v//')"
        NVIM_MAJOR="$(echo "$NVIM_VER" | cut -d. -f1)"
        NVIM_MINOR="$(echo "$NVIM_VER" | cut -d. -f2)"
        if [ "$NVIM_MAJOR" -eq 0 ] && [ "$NVIM_MINOR" -lt 9 ]; then
            log "System Neovim is older ($NVIM_VER). Downloading latest stable Neovim AppImage..."
            curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
            chmod u+x nvim.appimage
            ./nvim.appimage --appimage-extract >/dev/null 2>&1
            sudo mv squashfs-root /opt/nvim >/dev/null 2>&1 || mv squashfs-root "$HOME/.local/nvim"
            ln -sf "$HOME/.local/nvim/usr/bin/nvim" "$HOME/.local/bin/nvim" 2>/dev/null || true
            rm -f nvim.appimage
        fi
    fi
fi

# 2. Symlink Neovim config with .bak backup
mkdir -p "$HOME/.config"
if [ -d "$DOTFILES_DIR/nvim" ]; then
    if [ -e "$HOME/.config/nvim" ] || [ -L "$HOME/.config/nvim" ]; then
        if [ "$(readlink "$HOME/.config/nvim" 2>/dev/null)" != "$DOTFILES_DIR/nvim" ]; then
            log "Backing up existing ~/.config/nvim to ~/.config/nvim.bak..."
            cp -r "$HOME/.config/nvim" "$HOME/.config/nvim.bak" 2>/dev/null || mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak"
            success "Created backup at ~/.config/nvim.bak"
        fi
    fi

    ln -sfn "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
    success "Linked ~/.config/nvim -> $DOTFILES_DIR/nvim"
fi

# 3. Bootstrap & Sync Plugins (Headless)
if [ "$MODE" = "--full" ] && command -v nvim &>/dev/null; then
    log "Syncing Neovim plugins headlessly..."
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
fi

success "Neovim setup complete!"
