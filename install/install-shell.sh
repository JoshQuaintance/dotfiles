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

# Ensure UTF-8 locale is generated on Linux if tool is present
if [ "$OS" = "Linux" ]; then
    if command -v locale-gen &>/dev/null; then
        run_sudo locale-gen en_US.UTF-8 2>/dev/null || true
    elif command -v localedef &>/dev/null; then
        run_sudo localedef -i en_US -f UTF-8 en_US.UTF-8 2>/dev/null || true
    fi
fi

# 2. Set Zsh as default shell if not already
CURRENT_SHELL="$(basename "$SHELL")"
if [ "$CURRENT_SHELL" != "zsh" ] && command -v zsh &>/dev/null; then
    ZSH_PATH="$(which zsh)"
    log "Setting Zsh ($ZSH_PATH) as default shell..."
    chsh -s "$ZSH_PATH" "$USER" 2>/dev/null || run_sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null || true
fi

# 3. Symlink Zsh & Git configurations via shared link_dotfile helper
link_dotfile "zsh/.zshrc" "$HOME/.zshrc"
link_dotfile "zsh/.zshenv" "$HOME/.zshenv"
link_dotfile "zsh/.aliases" "$HOME/.aliases"

# Migrate personal Git credentials to ~/.gitconfig.local before linking ~/.gitconfig
if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ] && [ ! -f "$HOME/.gitconfig.local" ]; then
    log "Migrating personal Git credentials to ~/.gitconfig.local..."
    cp "$HOME/.gitconfig" "$HOME/.gitconfig.local"
    success "Preserved personal credentials at ~/.gitconfig.local"
fi
link_dotfile "config/git/.gitconfig" "$HOME/.gitconfig"
link_dotfile "config/git/.gitignore_global" "$HOME/.gitignore_global"

# Shared SSH defaults: prepend an Include so host entries in ~/.ssh/config stay personal
SSH_INCLUDE="Include $DOTFILES_DIR/config/ssh/dotfiles.conf"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if ! grep -qsF "$SSH_INCLUDE" "$HOME/.ssh/config"; then
    { echo "$SSH_INCLUDE"; echo; cat "$HOME/.ssh/config" 2>/dev/null; } > "$HOME/.ssh/config.tmp"
    mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    success "Added shared SSH defaults to ~/.ssh/config"
fi

success "Zsh shell and Git environment setup complete!"
