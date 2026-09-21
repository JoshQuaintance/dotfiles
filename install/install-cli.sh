#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Installing Core CLI Utilities (ripgrep, fd, fzf, zoxide, starship, eza, atuin, bat)..."

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

if command -v brew &>/dev/null; then
    ensure_homebrew
    log "Homebrew detected! Managing requested CLI tools..."
    
    # If no specific tools or --all requested, run brew bundle with the Brewfile
    if [ "${#REQUESTED_TOOLS[@]}" -eq 0 ] || [ "${REQUESTED_TOOLS[0]}" = "--all" ]; then
        if [ -f "$DOTFILES_DIR/Brewfile" ]; then
            log "Running brew bundle with $DOTFILES_DIR/Brewfile..."
            brew bundle --file="$DOTFILES_DIR/Brewfile"
        fi
    else
        # Install only specifically requested tools
        for pkg in "${REQUESTED_TOOLS[@]}"; do
            case "$pkg" in
                ripgrep|fd|fzf|zoxide|starship|eza|atuin|bat|yazi|dust|btop|fzf-tab|git|lazygit)
                    if brew list "$pkg" &>/dev/null; then
                        ask_update_tool "$pkg" "$(brew info "$pkg" 2>/dev/null | head -n 1 | awk '{print $3}')" DO_UPD
                        [ "$DO_UPD" = true ] && brew upgrade "$pkg" 2>/dev/null || true
                    else
                        brew install "$pkg"
                    fi
                    ;;
                ghostty|visual-studio-code|font-jetbrains-mono-nerd-font|font-miracode|font-fira-code-nerd-font|font-monocraft)
                    if [ "$OS" = "Darwin" ]; then
                        if brew list --cask "$pkg" &>/dev/null; then
                            log "$pkg is already installed."
                        else
                            brew install --cask "$pkg"
                        fi
                    fi
                    ;;
                genignore)
                    # Handled by bin linking below
                    ;;
            esac
        done
    fi

elif [ "$OS" = "Linux" ]; then
    ARCH="$(uname -m)"

    if command -v apt-get &>/dev/null; then
        # Ubuntu / Debian
        log "Ensuring base CLI packages via apt..."
        run_sudo apt-get update -y
        run_sudo apt-get install -y curl wget git build-essential ripgrep fd-find fzf bat tar gzip unzip
        
        # Link fdfind -> fd and batcat -> bat if necessary on Debian/Ubuntu
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
            [ "$(id -u)" -eq 0 ] && ln -sf "$(which fdfind)" "/usr/local/bin/fd" 2>/dev/null || true
        fi
        if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
            ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
            [ "$(id -u)" -eq 0 ] && ln -sf "$(which batcat)" "/usr/local/bin/bat" 2>/dev/null || true
        fi
    elif command -v dnf &>/dev/null; then
        # Fedora / RHEL
        log "Ensuring base CLI packages via dnf..."
        run_sudo dnf install -y curl wget git make gcc ripgrep fd-find fzf eza bat tar gzip unzip
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
            [ "$(id -u)" -eq 0 ] && ln -sf "$(which fdfind)" "/usr/local/bin/fd" 2>/dev/null || true
        fi
    elif command -v pacman &>/dev/null; then
        # Arch Linux
        run_sudo pacman -S --noconfirm --needed curl wget git base-devel ripgrep fd fzf eza atuin bat tar gzip unzip
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

    # 5. dust (standalone binary)
    if is_tool_requested "dust"; then
        if ! command -v dust &>/dev/null; then
            log "Installing dust..."
            DUST_ARCH="x86_64-unknown-linux-musl"
            [ "$ARCH" = "aarch64" -o "$ARCH" = "arm64" ] && DUST_ARCH="aarch64-unknown-linux-musl"
            curl -fsSL "https://github.com/bootandy/dust/releases/latest/download/dust-v1.1.1-${DUST_ARCH}.tar.gz" 2>/dev/null | tar -xz -C "/tmp" 2>/dev/null || true
            if [ -f "/tmp/dust-v1.1.1-${DUST_ARCH}/dust" ]; then
                mv "/tmp/dust-v1.1.1-${DUST_ARCH}/dust" "$HOME/.local/bin/dust"
                chmod +x "$HOME/.local/bin/dust"
                rm -rf "/tmp/dust-v1.1.1-${DUST_ARCH}"
                success "dust ready!"
            fi
        fi
    fi

    # 6. btop
    if is_tool_requested "btop"; then
        if ! command -v btop &>/dev/null; then
            if command -v apt-get &>/dev/null; then
                run_sudo apt-get install -y btop 2>/dev/null || true
            elif command -v dnf &>/dev/null; then
                run_sudo dnf install -y btop 2>/dev/null || true
            elif command -v pacman &>/dev/null; then
                run_sudo pacman -S --noconfirm btop 2>/dev/null || true
            fi
        fi
    fi

    # 7. fzf-tab (clone to ~/.local/share/fzf-tab if not present)
    if is_tool_requested "fzf-tab"; then
        if [ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/fzf-tab" ]; then
            log "Installing fzf-tab..."
            mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}"
            git clone --depth 1 https://github.com/Aloxaf/fzf-tab "${XDG_DATA_HOME:-$HOME/.local/share}/fzf-tab" 2>/dev/null || true
            success "fzf-tab ready!"
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

# Symlink Ghostty configuration
if [ -f "$DOTFILES_DIR/ghostty/config" ]; then
    mkdir -p "$HOME/.config/ghostty"
    ln -sfn "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"
    success "Linked ~/.config/ghostty/config -> $DOTFILES_DIR/ghostty/config"

    if [ "$OS" = "Darwin" ]; then
        mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
        ln -sfn "$DOTFILES_DIR/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
        ln -sfn "$DOTFILES_DIR/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
    fi
fi

# Symlink bat configuration
if [ -f "$DOTFILES_DIR/bat/config" ]; then
    mkdir -p "$HOME/.config/bat"
    ln -sfn "$DOTFILES_DIR/bat/config" "$HOME/.config/bat/config"
    success "Linked ~/.config/bat/config -> $DOTFILES_DIR/bat/config"
fi

# Symlink eza theme configuration
if [ -f "$DOTFILES_DIR/eza/theme.yml" ]; then
    mkdir -p "$HOME/.config/eza"
    ln -sfn "$DOTFILES_DIR/eza/theme.yml" "$HOME/.config/eza/theme.yml"
    success "Linked ~/.config/eza/theme.yml -> $DOTFILES_DIR/eza/theme.yml"

    if [ "$OS" = "Darwin" ]; then
        mkdir -p "$HOME/Library/Application Support/eza"
        ln -sfn "$DOTFILES_DIR/eza/theme.yml" "$HOME/Library/Application Support/eza/theme.yml"
        success "Linked ~/Library/Application Support/eza/theme.yml -> $DOTFILES_DIR/eza/theme.yml"
    fi
fi

# Symlink standalone bin utilities (dotupdate, dotcheck, dotdoctor, git-prompt-dir, esdiff, killport)
if [ -d "$DOTFILES_DIR/bin" ]; then
    for tool in "$DOTFILES_DIR/bin/"*; do
        if [ -f "$tool" ] && [ -x "$tool" ]; then
            tool_name="$(basename "$tool")"
            ln -sf "$tool" "$HOME/.local/bin/$tool_name"
            [ "$(id -u)" -eq 0 ] && ln -sf "$tool" "/usr/local/bin/$tool_name" 2>/dev/null || true
            success "Installed tool: $tool_name -> ~/.local/bin/$tool_name"
        fi
    done

    # Dot-prefixed shortcuts (.doctor, .check, .update, .dotdoctor, .dotcheck, .dotupdate)
    ln -sf "$DOTFILES_DIR/bin/dotdoctor" "$HOME/.local/bin/.doctor"
    ln -sf "$DOTFILES_DIR/bin/dotdoctor" "$HOME/.local/bin/.dotdoctor"
    ln -sf "$DOTFILES_DIR/bin/dotcheck" "$HOME/.local/bin/.check"
    ln -sf "$DOTFILES_DIR/bin/dotcheck" "$HOME/.local/bin/.dotcheck"
    ln -sf "$DOTFILES_DIR/bin/dotupdate" "$HOME/.local/bin/.update"
    ln -sf "$DOTFILES_DIR/bin/dotupdate" "$HOME/.local/bin/.dotupdate"
fi

success "All Core CLI utilities & shell tools configured successfully!"
