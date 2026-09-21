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
    log "Installing Oh My Zsh (single-branch)..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
fi
# Enforce single-branch tracking and prune any extra branches from Oh My Zsh
if [ -d "$HOME/.oh-my-zsh/.git" ]; then
    git -C "$HOME/.oh-my-zsh" config remote.origin.fetch "+refs/heads/master:refs/remotes/origin/master" 2>/dev/null || true
    git -C "$HOME/.oh-my-zsh" remote prune origin 2>/dev/null || true
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

# Symlink .zshenv for global environment & UTF-8 consistency
if [ -f "$DOTFILES_DIR/.zshenv" ]; then
    ln -sfn "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
    success "Linked ~/.zshenv -> $DOTFILES_DIR/.zshenv"
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

# 6. Global Git Configuration & Identity Migration
if [ -f "$DOTFILES_DIR/.gitconfig" ]; then
    if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then
        if [ ! -f "$HOME/.gitconfig.local" ]; then
            log "Migrating personal Git credentials to ~/.gitconfig.local..."
            cp "$HOME/.gitconfig" "$HOME/.gitconfig.local"
            success "Preserved personal credentials at ~/.gitconfig.local"
        fi
        log "Backing up existing ~/.gitconfig to ~/.gitconfig.bak..."
        cp -L "$HOME/.gitconfig" "$HOME/.gitconfig.bak" 2>/dev/null || mv "$HOME/.gitconfig" "$HOME/.gitconfig.bak"
    fi

    ln -sfn "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
    success "Linked ~/.gitconfig -> $DOTFILES_DIR/.gitconfig"
fi

# 7. Global Git Ignore
if [ -f "$DOTFILES_DIR/.gitignore_global" ]; then
    if [ -f "$HOME/.gitignore_global" ] && [ ! -L "$HOME/.gitignore_global" ]; then
        cp -L "$HOME/.gitignore_global" "$HOME/.gitignore_global.bak" 2>/dev/null || true
    fi
    ln -sfn "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global"
    success "Linked ~/.gitignore_global -> $DOTFILES_DIR/.gitignore_global"
fi

success "Zsh shell and Git environment setup complete!"
