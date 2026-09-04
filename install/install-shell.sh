#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Setting up Zsh Shell & Configurations..."

# 1. Install Zsh if missing
if ! command -v zsh &>/dev/null; then
    log "Installing Zsh..."
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew install zsh
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            run_sudo apt-get install -y zsh
        elif command -v dnf &>/dev/null; then
            run_sudo dnf install -y zsh
        elif command -v pacman &>/dev/null; then
            run_sudo pacman -S --noconfirm zsh
        fi
    fi
fi

# 2. Set Zsh as default shell if not already
CURRENT_SHELL="$(basename "$SHELL")"
if [ "$CURRENT_SHELL" != "zsh" ] && command -v zsh &>/dev/null; then
    ZSH_PATH="$(which zsh)"
    log "Setting Zsh ($ZSH_PATH) as default shell..."
    chsh -s "$ZSH_PATH" "$USER" 2>/dev/null || run_sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null || true
fi

# 3. Install Oh My Zsh if missing
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
fi

# 4. Symlink .zshrc with .bak backup
if [ -f "$DOTFILES_DIR/.zshrc" ]; then
    if [ -e "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ]; then
        if [ "$(readlink "$HOME/.zshrc" 2>/dev/null)" != "$DOTFILES_DIR/.zshrc" ]; then
            log "Backing up existing ~/.zshrc to ~/.zshrc.bak..."
            cp -L "$HOME/.zshrc" "$HOME/.zshrc.bak" 2>/dev/null || mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
            success "Created backup at ~/.zshrc.bak"
        fi
    fi

    ln -sfn "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
    success "Linked ~/.zshrc -> $DOTFILES_DIR/.zshrc"
fi

# 5. Symlink .aliases with .bak backup
if [ -f "$DOTFILES_DIR/.aliases" ]; then
    if [ -e "$HOME/.aliases" ] || [ -L "$HOME/.aliases" ]; then
        if [ "$(readlink "$HOME/.aliases" 2>/dev/null)" != "$DOTFILES_DIR/.aliases" ]; then
            log "Backing up existing ~/.aliases to ~/.aliases.bak..."
            cp -L "$HOME/.aliases" "$HOME/.aliases.bak" 2>/dev/null || mv "$HOME/.aliases" "$HOME/.aliases.bak"
            success "Created backup at ~/.aliases.bak"
        fi
    fi

    ln -sfn "$DOTFILES_DIR/.aliases" "$HOME/.aliases"
    success "Linked ~/.aliases -> $DOTFILES_DIR/.aliases"
fi

success "Zsh shell setup complete!"
