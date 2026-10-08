#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Installing Core CLI Utilities (ripgrep, fd, fzf, zoxide, spaceship, eza, atuin, bat)..."

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
                ripgrep|fd|fzf|zoxide|spaceship|eza|atuin|bat|yazi|dust|btop|tlrc|tokei|hyperfine|fzf-tab|zsh-autosuggestions|zsh-syntax-highlighting|git|git-delta|lazygit|glow|trash-cli)
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
        run_sudo apt-get install -y curl wget git build-essential ripgrep fd-find fzf bat trash-cli tar gzip unzip
        
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
        run_sudo dnf install -y curl wget git make gcc ripgrep fd-find fzf eza bat trash-cli tar gzip unzip
        if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
            [ "$(id -u)" -eq 0 ] && ln -sf "$(which fdfind)" "/usr/local/bin/fd" 2>/dev/null || true
        fi
    elif command -v pacman &>/dev/null; then
        # Arch Linux
        run_sudo pacman -S --noconfirm --needed curl wget git base-devel ripgrep fd fzf eza atuin bat git-delta glow tlrc tokei hyperfine zsh-autosuggestions zsh-syntax-highlighting trash-cli tar gzip unzip
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

    # 3. Atuin
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

    # 4. yazi (standalone binary + ya CLI)
    if is_tool_requested "yazi"; then
        if ! command -v yazi &>/dev/null; then
            log "Installing yazi..."
            YAZI_ARCH="x86_64-unknown-linux-musl"
            [ "$ARCH" = "aarch64" -o "$ARCH" = "arm64" ] && YAZI_ARCH="aarch64-unknown-linux-musl"
            rm -rf "/tmp/yazi-${YAZI_ARCH}" "/tmp/yazi.zip"
            if curl -fsSL "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${YAZI_ARCH}.zip" -o "/tmp/yazi.zip" 2>/dev/null; then
                unzip -q "/tmp/yazi.zip" -d "/tmp" 2>/dev/null || true
                if [ -f "/tmp/yazi-${YAZI_ARCH}/yazi" ]; then
                    mv "/tmp/yazi-${YAZI_ARCH}/yazi" "$HOME/.local/bin/yazi"
                    [ -f "/tmp/yazi-${YAZI_ARCH}/ya" ] && mv "/tmp/yazi-${YAZI_ARCH}/ya" "$HOME/.local/bin/ya"
                    chmod +x "$HOME/.local/bin/yazi" "$HOME/.local/bin/ya" 2>/dev/null || true
                    [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/yazi" "/usr/local/bin/yazi" 2>/dev/null || true
                    [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/ya" ] && ln -sf "$HOME/.local/bin/ya" "/usr/local/bin/ya" 2>/dev/null || true
                    success "yazi ready!"
                fi
                rm -rf "/tmp/yazi-${YAZI_ARCH}" "/tmp/yazi.zip"
            fi
        fi
    fi

    # 5. dust (standalone binary)
    if is_tool_requested "dust"; then
        if ! command -v dust &>/dev/null; then
            log "Installing dust..."
            DUST_ARCH="x86_64-unknown-linux-musl"
            [ "$ARCH" = "aarch64" -o "$ARCH" = "arm64" ] && DUST_ARCH="aarch64-unknown-linux-musl"
            DUST_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/bootandy/dust/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')"
            [ -z "$DUST_TAG" ] && DUST_TAG="v1.2.6"
            rm -rf "/tmp/dust-extract" && mkdir -p "/tmp/dust-extract"
            curl -fsSL "https://github.com/bootandy/dust/releases/download/${DUST_TAG}/dust-${DUST_TAG}-${DUST_ARCH}.tar.gz" 2>/dev/null | tar -xz --strip-components=1 -C "/tmp/dust-extract" 2>/dev/null || true
            if [ -f "/tmp/dust-extract/dust" ]; then
                mv "/tmp/dust-extract/dust" "$HOME/.local/bin/dust"
                chmod +x "$HOME/.local/bin/dust"
                [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/dust" "/usr/local/bin/dust" 2>/dev/null || true
                success "dust ready!"
            fi
            rm -rf "/tmp/dust-extract"
        fi
    fi

    # 6. git-delta (package manager or standalone binary)
    if is_tool_requested "git-delta" || is_tool_requested "delta"; then
        if ! command -v delta &>/dev/null; then
            log "Installing git-delta..."
            if command -v apt-get &>/dev/null; then
                run_sudo apt-get install -y git-delta 2>/dev/null || true
            elif command -v dnf &>/dev/null; then
                run_sudo dnf install -y git-delta 2>/dev/null || true
            fi
            if ! command -v delta &>/dev/null; then
                DELTA_ARCH="x86_64-unknown-linux-musl"
                [ "$ARCH" = "aarch64" -o "$ARCH" = "arm64" ] && DELTA_ARCH="aarch64-unknown-linux-gnu"
                DELTA_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/dandavison/delta/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')"
                [ -z "$DELTA_TAG" ] && DELTA_TAG="0.20.1"
                rm -rf "/tmp/delta-extract" && mkdir -p "/tmp/delta-extract"
                curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_TAG}/delta-${DELTA_TAG}-${DELTA_ARCH}.tar.gz" 2>/dev/null | tar -xz --strip-components=1 -C "/tmp/delta-extract" 2>/dev/null || true
                if [ -f "/tmp/delta-extract/delta" ]; then
                    mv "/tmp/delta-extract/delta" "$HOME/.local/bin/delta"
                    chmod +x "$HOME/.local/bin/delta"
                    [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/delta" "/usr/local/bin/delta" 2>/dev/null || true
                    success "git-delta ready!"
                fi
                rm -rf "/tmp/delta-extract"
            fi
        fi
    fi

    # 7. btop, tlrc (tldr), tokei, hyperfine
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

    if is_tool_requested "tlrc" || is_tool_requested "tldr"; then
        if ! command -v tldr &>/dev/null; then
            log "Installing tlrc (tldr)..."
            TLRC_ARCH="x86_64-unknown-linux-musl"
            [ "$ARCH" = "aarch64" -o "$ARCH" = "arm64" ] && TLRC_ARCH="aarch64-unknown-linux-musl"
            TLRC_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/tldr-pages/tlrc/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')"
            [ -z "$TLRC_TAG" ] && TLRC_TAG="v1.13.1"
            curl -fsSL "https://github.com/tldr-pages/tlrc/releases/download/${TLRC_TAG}/tlrc-${TLRC_TAG}-${TLRC_ARCH}.tar.gz" 2>/dev/null | tar -xz -C "$HOME/.local/bin" tldr 2>/dev/null || \
                (command -v apt-get &>/dev/null && run_sudo apt-get install -y tealdeer 2>/dev/null) || true
            chmod +x "$HOME/.local/bin/tldr" 2>/dev/null || true
            [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/tldr" ] && ln -sf "$HOME/.local/bin/tldr" "/usr/local/bin/tldr" 2>/dev/null || true
        fi
    fi

    if is_tool_requested "tokei"; then
        if ! command -v tokei &>/dev/null; then
            log "Installing tokei..."
            if command -v apt-get &>/dev/null; then
                run_sudo apt-get install -y tokei 2>/dev/null || true
            elif command -v dnf &>/dev/null; then
                run_sudo dnf install -y tokei 2>/dev/null || true
            fi
        fi
    fi

    if is_tool_requested "hyperfine"; then
        if ! command -v hyperfine &>/dev/null; then
            log "Installing hyperfine..."
            if command -v apt-get &>/dev/null; then
                run_sudo apt-get install -y hyperfine 2>/dev/null || true
            elif command -v dnf &>/dev/null; then
                run_sudo dnf install -y hyperfine 2>/dev/null || true
            fi
        fi
    fi

    # 8. glow (Markdown renderer, standalone binary; Ubuntu/Debian don't package it)
    if is_tool_requested "glow"; then
        if ! command -v glow &>/dev/null; then
            log "Installing glow..."
            GLOW_ARCH="x86_64"
            { [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; } && GLOW_ARCH="arm64"
            GLOW_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/charmbracelet/glow/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')"
            [ -z "$GLOW_TAG" ] && GLOW_TAG="v3.0.0"
            GLOW_VER="${GLOW_TAG#v}"
            rm -rf "/tmp/glow-extract" && mkdir -p "/tmp/glow-extract"
            curl -fsSL "https://github.com/charmbracelet/glow/releases/download/${GLOW_TAG}/glow_${GLOW_VER}_Linux_${GLOW_ARCH}.tar.gz" 2>/dev/null | tar -xz --strip-components=1 -C "/tmp/glow-extract" 2>/dev/null || true
            if [ -f "/tmp/glow-extract/glow" ]; then
                mv "/tmp/glow-extract/glow" "$HOME/.local/bin/glow"
                chmod +x "$HOME/.local/bin/glow"
                [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/glow" "/usr/local/bin/glow" 2>/dev/null || true
                success "glow ready!"
            fi
            rm -rf "/tmp/glow-extract"
        fi
    fi

    # 9. lazygit (standalone binary; not packaged on Ubuntu 24.04 / Debian stable)
    if is_tool_requested "lazygit"; then
        if ! command -v lazygit &>/dev/null; then
            log "Installing lazygit..."
            LG_ARCH="x86_64"
            { [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; } && LG_ARCH="arm64"
            LG_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazygit/releases/latest 2>/dev/null | awk -F'/' '{print $NF}')"
            [ -z "$LG_TAG" ] && LG_TAG="v0.66.0"
            rm -rf "/tmp/lazygit-extract" && mkdir -p "/tmp/lazygit-extract"
            curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${LG_TAG}/lazygit_${LG_TAG#v}_linux_${LG_ARCH}.tar.gz" 2>/dev/null | tar -xz -C "/tmp/lazygit-extract" lazygit 2>/dev/null || true
            if [ -f "/tmp/lazygit-extract/lazygit" ]; then
                mv "/tmp/lazygit-extract/lazygit" "$HOME/.local/bin/lazygit"
                chmod +x "$HOME/.local/bin/lazygit"
                [ "$(id -u)" -eq 0 ] && ln -sf "$HOME/.local/bin/lazygit" "/usr/local/bin/lazygit" 2>/dev/null || true
                success "lazygit ready!"
            fi
            rm -rf "/tmp/lazygit-extract"
        fi
    fi

    # 10. Spaceship Prompt & Zsh Plugins: fzf-tab, zsh-autosuggestions, zsh-syntax-highlighting
    if is_tool_requested "spaceship" && [ ! -d "$HOME/.spaceship-prompt" ]; then
        log "Installing Spaceship Zsh prompt..."
        git clone --depth 1 https://github.com/spaceship-prompt/spaceship-prompt.git "$HOME/.spaceship-prompt" 2>/dev/null || true
        success "Spaceship prompt ready!"
    fi
    mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}"
    if is_tool_requested "fzf-tab" && [ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/fzf-tab" ]; then
        log "Installing fzf-tab..."
        git clone --depth 1 https://github.com/Aloxaf/fzf-tab "${XDG_DATA_HOME:-$HOME/.local/share}/fzf-tab" 2>/dev/null || true
        success "fzf-tab ready!"
    fi
    if is_tool_requested "zsh-autosuggestions" && [ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-autosuggestions" ]; then
        log "Installing zsh-autosuggestions..."
        git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-autosuggestions" 2>/dev/null || true
        success "zsh-autosuggestions ready!"
    fi
    if is_tool_requested "zsh-syntax-highlighting" && [ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-syntax-highlighting" ]; then
        log "Installing zsh-syntax-highlighting..."
        git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-syntax-highlighting" 2>/dev/null || true
        success "zsh-syntax-highlighting ready!"
    fi

    # 11. Developer Fonts (Miracode, FiraCode NF, Monocraft)
    if is_tool_requested "fonts" || is_tool_requested "font-miracode" || is_tool_requested "font-fira-code-nerd-font"; then
        if [ -x "$DOTFILES_DIR/install/install-fonts.sh" ]; then
            bash "$DOTFILES_DIR/install/install-fonts.sh"
        fi
    fi
fi

# WSL integration (any package manager): win32yank for a UTF-8-safe clipboard, wslu for wslview/BROWSER
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
    if is_tool_requested "wsl" && ! command -v win32yank.exe &>/dev/null; then
        log "Installing win32yank (WSL clipboard)..."
        rm -rf "/tmp/win32yank-extract" && mkdir -p "/tmp/win32yank-extract"
        if curl -fsSL "https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip" -o "/tmp/win32yank-extract/win32yank.zip" 2>/dev/null; then
            unzip -q -o "/tmp/win32yank-extract/win32yank.zip" -d "/tmp/win32yank-extract" 2>/dev/null || true
            if [ -f "/tmp/win32yank-extract/win32yank.exe" ]; then
                mv "/tmp/win32yank-extract/win32yank.exe" "$HOME/.local/bin/win32yank.exe"
                chmod +x "$HOME/.local/bin/win32yank.exe"
                success "win32yank ready!"
            fi
        fi
        rm -rf "/tmp/win32yank-extract"
    fi
    if is_tool_requested "wsl" && ! command -v wslview &>/dev/null; then
        log "Installing wslu (wslview)..."
        if command -v apt-get &>/dev/null; then
            run_sudo apt-get install -y wslu 2>/dev/null || true
        else
            warn "wslu isn't packaged for this distro; 'open' falls back to explorer.exe"
        fi
    fi
fi

# Symlink CLI configurations via shared link_dotfile helper
link_dotfile "config/spaceship/spaceship.zsh" "$HOME/.config/spaceship.zsh"
link_dotfile "config/ghostty/config" "$HOME/.config/ghostty/config"
if [ "$OS" = "Darwin" ]; then
    link_dotfile "config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    link_dotfile "config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
fi
link_dotfile "config/bat/config" "$HOME/.config/bat/config"
link_dotfile "config/eza/theme.yml" "$HOME/.config/eza/theme.yml"
if [ "$OS" = "Darwin" ]; then
    link_dotfile "config/eza/theme.yml" "$HOME/Library/Application Support/eza/theme.yml"
fi
link_dotfile "config/yazi" "$HOME/.config/yazi"
link_dotfile "config/atuin/config.toml" "$HOME/.config/atuin/config.toml"
if [ "$OS" = "Darwin" ] && [ -z "${XDG_CONFIG_HOME:-}" ]; then
    link_dotfile "config/lazygit/config.yml" "$HOME/Library/Application Support/lazygit/config.yml"
else
    link_dotfile "config/lazygit/config.yml" "${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"
fi

# Symlink standalone bin utilities (dot, dotupdate, dotcheck, dotdoctor, dottest, esdiff, killport)
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
    ln -sf "$DOTFILES_DIR/bin/dottest" "$HOME/.local/bin/.test"
    ln -sf "$DOTFILES_DIR/bin/dottest" "$HOME/.local/bin/.dottest"
fi

success "All Core CLI utilities & shell tools configured successfully!"
