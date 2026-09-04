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

REQUESTED_TOOLS=("$@")
is_tool_requested() {
    local target="$1"
    if [ "${#REQUESTED_TOOLS[@]}" -eq 0 ] || [ "${REQUESTED_TOOLS[0]}" = "--all" ]; then
        return 0
    fi
    for t in "${REQUESTED_TOOLS[@]}"; do
        [ "$t" = "$target" ] && return 0
    done
    return 1
}

if [ "$OS" = "Darwin" ]; then
    ensure_homebrew
    log "Installing / Updating CLI tools via Homebrew..."
    for pkg in ripgrep fd fzf zoxide starship eza atuin; do
        if is_tool_requested "$pkg"; then
            if brew list "$pkg" &>/dev/null; then
                ask_update_tool "$pkg" "$(brew info "$pkg" 2>/dev/null | head -n 1 | awk '{print $3}')" DO_UPD
                if [ "$DO_UPD" = true ]; then
                    brew upgrade "$pkg" 2>/dev/null || true
                fi
            else
                brew install "$pkg"
            fi
        fi
    done

elif [ "$OS" = "Linux" ]; then
    ARCH="$(uname -m)"

    if command -v apt-get &>/dev/null; then
        # Ubuntu / Debian
        log "Ensuring base CLI packages via apt..."
        run_sudo apt-get update -y
        run_sudo apt-get install -y curl wget git build-essential ripgrep fd-find fzf tar gzip
        
        # Link fdfind -> fd if necessary on Debian/Ubuntu
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
            [ "$(id -u)" -eq 0 ] && ln -sf "$(which fdfind)" "/usr/local/bin/fd" 2>/dev/null || true
        fi
    elif command -v dnf &>/dev/null; then
        # Fedora / RHEL
        log "Ensuring base CLI packages via dnf..."
        run_sudo dnf install -y curl wget git make gcc ripgrep fd-find fzf eza tar gzip
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
            [ "$(id -u)" -eq 0 ] && ln -sf "$(which fdfind)" "/usr/local/bin/fd" 2>/dev/null || true
        fi
    elif command -v pacman &>/dev/null; then
        # Arch Linux
        run_sudo pacman -S --noconfirm --needed curl wget git base-devel ripgrep fd fzf eza atuin
    fi

    # 1. eza
    if is_tool_requested "eza"; then
        DO_EZA=true
        if command -v eza &>/dev/null; then
            ask_update_tool "eza" "$(eza --version 2>/dev/null | head -n 1 | awk '{print $1,$2}')" DO_EZA
        fi
        if [ "$DO_EZA" = true ]; then
            log "Installing / Updating eza (standalone binary)..."
            EZA_ARCH="x86_64-unknown-linux-gnu"
            if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                EZA_ARCH="aarch64-unknown-linux-gnu"
            fi
            curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz" | tar -xz -C "$HOME/.local/bin/"
            chmod +x "$HOME/.local/bin/eza" 2>/dev/null || true
            [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/eza" "/usr/local/bin/eza" 2>/dev/null || true
            success "eza ready!"
        fi
    fi

    # 2. zoxide
    if is_tool_requested "zoxide"; then
        DO_ZOXIDE=true
        if command -v zoxide &>/dev/null; then
            ask_update_tool "zoxide" "$(zoxide --version 2>/dev/null | head -n 1)" DO_ZOXIDE
        fi
        if [ "$DO_ZOXIDE" = true ]; then
            log "Installing / Updating zoxide..."
            curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
            [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/zoxide" "/usr/local/bin/zoxide" 2>/dev/null || true
        fi
    fi

    # 3. Starship prompt
    if is_tool_requested "starship"; then
        DO_STARSHIP=true
        if command -v starship &>/dev/null; then
            ask_update_tool "Starship" "$(starship --version 2>/dev/null | head -n 1 | awk '{print $1,$2}')" DO_STARSHIP
        fi
        if [ "$DO_STARSHIP" = true ]; then
            log "Installing / Updating Starship prompt..."
            curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
            chmod +x "$HOME/.local/bin/starship" 2>/dev/null || true
            [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/starship" "/usr/local/bin/starship" 2>/dev/null || true
            success "Starship ready!"
        fi
    fi

    # 4. Atuin
    if is_tool_requested "atuin"; then
        DO_ATUIN=true
        if command -v atuin &>/dev/null || [ -f "$HOME/.atuin/bin/atuin" ]; then
            ask_update_tool "Atuin" "$(atuin --version 2>/dev/null | head -n 1)" DO_ATUIN
        fi
        if [ "$DO_ATUIN" = true ]; then
            log "Installing / Updating Atuin (shell history)..."
            curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh | sh -s -- --no-modify-path 2>/dev/null || true
        fi
    fi
fi

# Symlink Starship prompt configuration with backup
if is_tool_requested "starship"; then
    mkdir -p "$HOME/.config"
    if [ -f "$DOTFILES_DIR/starship/starship.toml" ]; then
        if [ -f "$HOME/.config/starship.toml" ] && [ ! -L "$HOME/.config/starship.toml" ]; then
            BACKUP_STARSHIP="$HOME/.config/starship.toml.bak"
            [ -e "$BACKUP_STARSHIP" ] && BACKUP_STARSHIP="$HOME/.config/starship.toml.bak.$(date +%Y%m%d%H%M%S)"
            cp "$HOME/.config/starship.toml" "$BACKUP_STARSHIP"
        fi
        ln -sfn "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
        success "Linked ~/.config/starship.toml -> $DOTFILES_DIR/starship/starship.toml"
    fi
fi

# Symlink standalone bin utilities (like genignore)
if [ -d "$DOTFILES_DIR/bin" ]; then
    for tool in "$DOTFILES_DIR/bin/"*; do
        if [ -f "$tool" ] && [ -x "$tool" ]; then
            tool_name="$(basename "$tool")"
            if is_tool_requested "$tool_name"; then
                ln -sf "$tool" "$HOME/.local/bin/$tool_name"
                [ "$(id -u)" -eq 0 ] && ln -sf "$tool" "/usr/local/bin/$tool_name" 2>/dev/null || true
                success "Installed tool: $tool_name -> ~/.local/bin/$tool_name"
            fi
        fi
    done
fi

success "All Core CLI utilities & shell tools configured successfully!"
