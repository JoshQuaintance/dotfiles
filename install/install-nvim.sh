#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODE="${1:---full}"
log "Setting up Neovim & Treesitter (Mode: $MODE)..."

# 1. Check if Neovim is already installed
DO_INSTALL_NVIM=true
if command -v nvim &>/dev/null; then
    CURRENT_NVIM_VER="$(nvim --version | head -n 1 | awk '{print $2}')"
    ask_update_tool "Neovim" "$CURRENT_NVIM_VER" DO_INSTALL_NVIM
fi

if [ "$DO_INSTALL_NVIM" = true ]; then
    log "Installing / Updating to latest stable Neovim..."

    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew upgrade neovim 2>/dev/null || brew install neovim
        brew upgrade tree-sitter-cli 2>/dev/null || brew install tree-sitter-cli

    elif [ "$OS" = "Linux" ]; then
        ensure_base_deps
        
        # Download official pre-built static binary release (guarantees latest stable Neovim >= 0.10)
        NVIM_TAR="nvim-linux-x86_64.tar.gz"
        NVIM_DIR_NAME="nvim-linux-x86_64"
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            NVIM_TAR="nvim-linux-arm64.tar.gz"
            NVIM_DIR_NAME="nvim-linux-arm64"
        fi

        log "Fetching latest official Neovim binary ($NVIM_TAR)..."
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/${NVIM_TAR}" | tar -xz -C "$HOME/.local/"
        
        if [ -f "$HOME/.local/${NVIM_DIR_NAME}/bin/nvim" ]; then
            ln -sf "$HOME/.local/${NVIM_DIR_NAME}/bin/nvim" "$HOME/.local/bin/nvim"
            [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/${NVIM_DIR_NAME}/bin/nvim" "/usr/local/bin/nvim" 2>/dev/null || true
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
            [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/tree-sitter" "/usr/local/bin/tree-sitter" 2>/dev/null || true
        fi
    fi
else
    log "Keeping existing Neovim installation ($CURRENT_NVIM_VER)."
    # Check for version compatibility warning
    NVIM_NUM="$(echo "$CURRENT_NVIM_VER" | sed 's/v//')"
    NVIM_MAJOR="$(echo "$NVIM_NUM" | cut -d. -f1)"
    NVIM_MINOR="$(echo "$NVIM_NUM" | cut -d. -f2)"
    if [ "$NVIM_MAJOR" -eq 0 ] && [ "$NVIM_MINOR" -lt 9 ]; then
        warn "Existing Neovim version ($CURRENT_NVIM_VER) is older than 0.9. Some modern plugins may require an update."
    fi
fi

if command -v nvim &>/dev/null; then
    success "Neovim is ready ($(nvim --version | head -n 1))"
fi

# 2. Symlink Neovim config with safe backup
mkdir -p "$HOME/.config"
if [ -d "$DOTFILES_DIR/nvim" ]; then
    if [ -e "$HOME/.config/nvim" ] || [ -L "$HOME/.config/nvim" ]; then
        if [ "$(readlink "$HOME/.config/nvim" 2>/dev/null)" != "$DOTFILES_DIR/nvim" ]; then
            BACKUP_TARGET="$HOME/.config/nvim.bak"
            if [ -e "$BACKUP_TARGET" ]; then
                BACKUP_TARGET="$HOME/.config/nvim.bak.$(date +%Y%m%d%H%M%S)"
            fi
            log "Backing up existing ~/.config/nvim to $BACKUP_TARGET..."
            mv "$HOME/.config/nvim" "$BACKUP_TARGET"
            success "Created backup at $BACKUP_TARGET"
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
