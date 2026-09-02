#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Installing Core CLI Utilities (ripgrep, fd, fzf, zoxide, starship, eza)..."

if [ "$OS" = "Darwin" ]; then
    ensure_homebrew
    log "Installing CLI tools via Homebrew..."
    brew install ripgrep fd fzf zoxide starship eza

elif [ "$OS" = "Linux" ]; then
    if command -v apt-get &>/dev/null; then
        # Ubuntu / Debian
        log "Installing base CLI packages via apt..."
        sudo apt-get update -y
        sudo apt-get install -y curl git build-essential ripgrep fd-find fzf
        
        # Link fdfind -> fd if necessary on Debian/Ubuntu
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        fi
    elif command -v dnf &>/dev/null; then
        # Fedora / RHEL
        log "Installing base CLI packages via dnf..."
        sudo dnf install -y curl git make gcc ripgrep fd-find fzf
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        fi
    elif command -v pacman &>/dev/null; then
        # Arch Linux fallback
        sudo pacman -S --noconfirm --needed curl git base-devel ripgrep fd fzf eza
    fi

    # Install zoxide via official installer
    if ! command -v zoxide &>/dev/null; then
        log "Installing zoxide..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi

    # Install Starship prompt via official installer
    if ! command -v starship &>/dev/null; then
        log "Installing Starship prompt..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
fi

# Symlink Starship prompt configuration
mkdir -p "$HOME/.config"
if [ -f "$DOTFILES_DIR/starship/starship.toml" ]; then
    if [ -f "$HOME/.config/starship.toml" ] && [ ! -L "$HOME/.config/starship.toml" ]; then
        cp "$HOME/.config/starship.toml" "$HOME/.config/starship.toml.bak"
    fi
    ln -sfn "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
    success "Linked ~/.config/starship.toml -> $DOTFILES_DIR/starship/starship.toml"
fi

# Symlink standalone bin utilities (like genignore)
mkdir -p "$HOME/.local/bin"
if [ -d "$DOTFILES_DIR/bin" ]; then
    log "Installing standalone dotfiles utilities into ~/.local/bin..."
    for tool in "$DOTFILES_DIR/bin/"*; do
        if [ -f "$tool" ] && [ -x "$tool" ]; then
            tool_name="$(basename "$tool")"
            ln -sf "$tool" "$HOME/.local/bin/$tool_name"
            success "Installed tool: $tool_name -> ~/.local/bin/$tool_name"
        fi
    done
fi

success "Core CLI utilities & Starship installed successfully!"
