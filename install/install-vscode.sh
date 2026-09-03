#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

EXTENSIONS_JSON="$DOTFILES_DIR/vscode/extensions.json"

log "Setting up Visual Studio Code & Modular Extensions..."

# 1. Install or update VSCode application
DO_CODE=true
if command -v code &>/dev/null; then
    CODE_VER="$(code --version 2>/dev/null | head -n 1 || true)"
    ask_update_tool "VSCode" "$CODE_VER" DO_CODE
fi

if [ "$DO_CODE" = true ]; then
    log "Installing / Updating Visual Studio Code..."
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        brew upgrade --cask visual-studio-code 2>/dev/null || brew install --cask visual-studio-code
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            # Ubuntu / Debian official repository
            run_sudo apt-get update -y
            run_sudo apt-get install -y wget gpg apt-transport-https
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
            run_sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            rm -f /tmp/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | run_sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            run_sudo apt-get update -y
            run_sudo apt-get install -y code
        elif command -v dnf &>/dev/null; then
            # Fedora official repository
            run_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            run_sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            run_sudo dnf check-update || true
            run_sudo dnf install -y code
        fi
    fi
fi

if command -v code &>/dev/null; then
    success "VSCode is ready ($(code --version 2>/dev/null | head -n 1 || echo 'ready'))"
else
    warn "Could not install VSCode binary automatically. Proceeding with configuration symlinks..."
fi

# 2. Determine platform-specific VSCode User configuration directory
if [ "$OS" = "Darwin" ]; then
    VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
elif [ "$OS" = "Linux" ]; then
    VSCODE_USER_DIR="$HOME/.config/Code/User"
fi

mkdir -p "$VSCODE_USER_DIR"

# 3. Backup & Symlink settings.json
if [ -f "$DOTFILES_DIR/vscode/settings.json" ]; then
    if [ -f "$VSCODE_USER_DIR/settings.json" ] && [ ! -L "$VSCODE_USER_DIR/settings.json" ]; then
        log "Backing up existing VSCode settings.json to settings.json.bak..."
        cp "$VSCODE_USER_DIR/settings.json" "$VSCODE_USER_DIR/settings.json.bak"
    fi
    ln -sfn "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_USER_DIR/settings.json"
    success "Linked VSCode settings.json"
fi

# 4. Backup & Symlink keybindings.json
if [ -f "$DOTFILES_DIR/vscode/keybindings.json" ]; then
    if [ -f "$VSCODE_USER_DIR/keybindings.json" ] && [ ! -L "$VSCODE_USER_DIR/keybindings.json" ]; then
        cp "$VSCODE_USER_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json.bak"
    fi
    ln -sfn "$DOTFILES_DIR/vscode/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
    success "Linked VSCode keybindings.json"
fi

# 5. Backup & Symlink snippets directory
if [ -d "$DOTFILES_DIR/vscode/snippets" ]; then
    if [ -d "$VSCODE_USER_DIR/snippets" ] && [ ! -L "$VSCODE_USER_DIR/snippets" ]; then
        cp -r "$VSCODE_USER_DIR/snippets" "$VSCODE_USER_DIR/snippets.bak"
    fi
    ln -sfn "$DOTFILES_DIR/vscode/snippets" "$VSCODE_USER_DIR/snippets"
    success "Linked VSCode snippets directory"
fi

# 6. Modular Extension Installation
if command -v code &>/dev/null && [ -f "$EXTENSIONS_JSON" ]; then
    # Extra flags if running as root in containers
    CODE_FLAGS=""
    if [ "$(id -u)" -eq 0 ]; then
        CODE_FLAGS="--no-sandbox --user-data-dir=$HOME/.config/Code"
    fi

    # Helper to parse extension groups using python3 or node
    get_group_extensions() {
        local group="$1"
        python3 -c "
import json, sys
data = json.load(open('$EXTENSIONS_JSON'))
if '$group' == 'all':
    for g in data.values():
        for ext in g.get('extensions', []):
            print(ext)
elif '$group' in data:
    for ext in data['$group'].get('extensions', []):
        print(ext)
" 2>/dev/null || node -e "
const data = require('$EXTENSIONS_JSON');
if ('$group' === 'all') {
    Object.values(data).forEach(g => (g.extensions || []).forEach(e => console.log(e)));
} else if (data['$group']) {
    (data['$group'].extensions || []).forEach(e => console.log(e));
}
" 2>/dev/null
    }

    # Determine which categories to install
    SELECTED_GROUPS=()

    if [ "$#" -gt 0 ]; then
        for arg in "$@"; do
            clean_arg="${arg#--}"
            SELECTED_GROUPS+=("$clean_arg")
        done
    else
        echo ""
        echo "=========================================="
        echo "    VSCode Extension Category Selection  "
        echo "=========================================="
        echo "  1) Install ALL extensions"
        echo "  2) Core only (Themes, Git, Prettier, ESLint, Neovim)"
        echo "  3) Interactive / Select by category"
        echo "  4) Skip extensions install"
        echo "=========================================="
        read -rp "Select option [1-4]: " ext_choice

        case "$ext_choice" in
            1|"")
                SELECTED_GROUPS=("all")
                ;;
            2)
                SELECTED_GROUPS=("core")
                ;;
            3)
                read -rp "  [+] Core tools (Themes, Git, ESLint, Prettier, Neovim)? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("core")
                read -rp "  [+] Web / TypeScript (Tailwind, Bun)? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("web")
                read -rp "  [+] Svelte / SvelteKit? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("svelte")
                read -rp "  [+] Angular? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("angular")
                read -rp "  [+] Python (Pylance, Black, Pylint)? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("python")
                read -rp "  [+] Java & Gradle? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("java")
                read -rp "  [+] Go? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("go")
                read -rp "  [+] Markdown, Mermaid & YAML? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("markdown_docs")
                read -rp "  [+] Remote SSH, WSL & Containers? [Y/n]: " a; [[ ! "$a" =~ ^[Nn]$ ]] && SELECTED_GROUPS+=("remote_cloud")
                ;;
            4)
                SELECTED_GROUPS=()
                ;;
        esac
    fi

    if [ "${#SELECTED_GROUPS[@]}" -gt 0 ]; then
        log "Syncing selected VSCode extension categories: ${SELECTED_GROUPS[*]}..."
        INSTALLED_EXTS="$(code $CODE_FLAGS --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"

        for group in "${SELECTED_GROUPS[@]}"; do
            EXTS=$(get_group_extensions "$group")
            for ext in $EXTS; do
                ext_lower="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
                if echo "$INSTALLED_EXTS" | grep -q "^${ext_lower}$"; then
                    success "Extension already installed: $ext"
                else
                    log "Installing extension: $ext..."
                    code $CODE_FLAGS --install-extension "$ext" --force >/dev/null 2>&1 || warn "Could not install: $ext"
                fi
            done
        done
        success "VSCode extensions sync complete!"
    else
        log "Skipped VSCode extensions install."
    fi
fi

success "VSCode setup complete!"
