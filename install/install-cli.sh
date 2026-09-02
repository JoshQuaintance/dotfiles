#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Installing Core CLI Utilities (ripgrep, fd, fzf, zoxide, starship, eza, atuin)..."

# Ensure local bin directory exists in PATH
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

if [ "$OS" = "Darwin" ]; then
    ensure_homebrew
    log "Installing CLI tools via Homebrew..."
    brew install ripgrep fd fzf zoxide starship eza atuin

elif [ "$OS" = "Linux" ]; then
    ARCH="$(uname -m)"

    if command -v apt-get &>/dev/null; then
        # Ubuntu / Debian
        log "Installing base CLI packages via apt..."
        sudo apt-get update -y
        sudo apt-get install -y curl wget git build-essential ripgrep fd-find fzf tar gzip
        
        # Link fdfind -> fd if necessary on Debian/Ubuntu
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        fi
    elif command -v dnf &>/dev/null; then
        # Fedora / RHEL
        log "Installing base CLI packages via dnf..."
        sudo dnf install -y curl wget git make gcc ripgrep fd-find fzf eza tar gzip
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        fi
    elif command -v pacman &>/dev/null; then
        # Arch Linux
        sudo pacman -S --noconfirm --needed curl wget git base-devel ripgrep fd fzf eza atuin
    fi

    # 1. Install eza on Linux if not already installed
    if ! command -v eza &>/dev/null; then
        log "Installing eza (standalone binary)..."
        EZA_ARCH="x86_64-unknown-linux-gnu"
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            EZA_ARCH="aarch64-unknown-linux-gnu"
        fi
        curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz" | tar -xz -C "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/eza" 2>/dev/null || true
        success "eza installed to ~/.local/bin/eza"
    fi

    # 2. Install zoxide via official installer
    if ! command -v zoxide &>/dev/null; then
        log "Installing zoxide..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi

    # 3. Install Starship prompt via official installer
    if ! command -v starship &>/dev/null; then
        log "Installing Starship prompt..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi

    # 4. Install Atuin (shell history) via official installer
    if ! command -v atuin &>/dev/null && [ ! -f "$HOME/.atuin/bin/atuin" ]; then
        log "Installing Atuin (shell history)..."
        curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh -s -- --no-modify-path 2>/dev/null || true
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

success "All Core CLI utilities & shell tools installed successfully!"
