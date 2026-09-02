#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODE="${1:---full}"
log "Setting up Neovim & Treesitter (Mode: $MODE)..."

# 1. Install Neovim
if [ "$OS" = "Darwin" ]; then
    ensure_homebrew
    brew install neovim tree-sitter-cli

elif [ "$OS" = "Linux" ]; then
    ensure_base_deps
    
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y neovim
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y neovim
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm neovim tree-sitter
    fi

    # Check if Neovim is < 0.9 on older Ubuntu, or missing -> install official AppImage or static binary
    NEED_MODERN_NVIM=false
    if ! command -v nvim &>/dev/null; then
        NEED_MODERN_NVIM=true
    else
        NVIM_VER="$(nvim --version | head -n 1 | awk '{print $2}' | sed 's/v//')"
        NVIM_MAJOR="$(echo "$NVIM_VER" | cut -d. -f1)"
        NVIM_MINOR="$(echo "$NVIM_VER" | cut -d. -f2)"
        if [ "$NVIM_MAJOR" -eq 0 ] && [ "$NVIM_MINOR" -lt 9 ]; then
            NEED_MODERN_NVIM=true
        fi
    fi

    if [ "$NEED_MODERN_NVIM" = true ]; then
        log "Installing latest modern Neovim release..."
        NVIM_TAR="nvim-linux-x86_64.tar.gz"
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            NVIM_TAR="nvim-linux-arm64.tar.gz"
        fi
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/${NVIM_TAR}" | tar -xz -C "$HOME/.local/"
        ln -sf "$HOME/.local/nvim-linux-${ARCH}/bin/nvim" "$HOME/.local/bin/nvim" 2>/dev/null || ln -sf "$HOME/.local/nvim-linux-x86_64/bin/nvim" "$HOME/.local/bin/nvim" 2>/dev/null || true
    fi

    # Ensure tree-sitter-cli is available for Treesitter parsers
    if ! command -v tree-sitter &>/dev/null; then
        log "Installing tree-sitter-cli binary..."
        TS_ARCH="tree-sitter-linux-x64.gz"
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            TS_ARCH="tree-sitter-linux-arm64.gz"
        fi
        curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/${TS_ARCH}" | gzip -d > "$HOME/.local/bin/tree-sitter" 2>/dev/null || true
        chmod +x "$HOME/.local/bin/tree-sitter" 2>/dev/null || true
    fi
fi

if command -v nvim &>/dev/null; then
    success "Neovim is ready ($(nvim --version | head -n 1))"
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
