#!/usr/bin/env bash
set -e

# Disable Zsh builtin log command if running under Zsh
disable -r log 2>/dev/null || true

# Repository configuration
DOTFILES_REPO="https://github.com/JoshQuaintance/dotfiles.git"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-interactive}"
RAW_BASE_URL="https://raw.githubusercontent.com/JoshQuaintance/dotfiles/${DOTFILES_BRANCH}"
DEFAULT_TARGET_DIR="$HOME/Codes/dotfiles"

# Determine if running from a local clone or remotely via curl
CURRENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$CURRENT_SCRIPT_DIR/install/common.sh" ]; then
    DOTFILES_DIR="$CURRENT_SCRIPT_DIR"
else
    DOTFILES_DIR="$DEFAULT_TARGET_DIR"
fi

# Load shared helpers from common.sh (locally if present, or dynamically via eval)
if [ -f "$DOTFILES_DIR/install/common.sh" ]; then
    source "$DOTFILES_DIR/install/common.sh"
else
    eval "$(curl -fsSL "$RAW_BASE_URL/install/common.sh")"
fi

# Ensure Git is installed and configure safe.directory
ensure_git
git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

# Helper to read from /dev/tty if stdin is piped (e.g. curl ... | bash), portable for both Bash and Zsh
read_input() {
    local prompt="$1"
    local var_name="$2"
    printf "%s" "$prompt"
    if [ -e /dev/tty ] && [ -r /dev/tty ] && (true < /dev/tty) 2>/dev/null; then
        read -r "$var_name" < /dev/tty
    else
        read -r "$var_name"
    fi
}

# Helper to launch into new shell automatically
launch_shell() {
    echo ""
    success "$1"
    if command -v zsh &>/dev/null; then
        log "Launching your new Zsh environment..."
        if [ -e /dev/tty ] && [ -r /dev/tty ] && (true < /dev/tty) 2>/dev/null; then
            exec zsh -l < /dev/tty
        else
            exec zsh -l
        fi
    fi
    exit 0
}

echo ""
echo "================================================="
echo "           Dotfiles Unified Installer            "
echo "================================================="
echo "  1) Full Workstation (Mac / Linux / WSL)"
echo "     → Full clone, all tools, Zsh, Neovim, VSCode, Mise, Astral."
echo ""
echo "  2) Server / Minimal (Headless VPS / Remote Server)"
echo "     → Fast Git sparse-checkout (only nvim, bin, .zshrc),"
echo "       lightweight setup with git pull update capability."
echo ""
echo "  3) Custom / Selective"
echo "     → Pick and choose specific components."
echo "================================================="
echo ""

CHOICE="$1"
if [ -z "$CHOICE" ]; then
    read_input "Select installation profile [1-3]: " CHOICE
fi

# ==========================================
# Option 1: Full Workstation
# ==========================================
if [[ "$CHOICE" == "1" || "$CHOICE" == "--workstation" || "$CHOICE" == "--all" ]]; then
    log "Setting up Full Workstation..."
    
    DOTFILES_DIR="$DEFAULT_TARGET_DIR"
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        log "Cloning dotfiles to $DOTFILES_DIR..."
        mkdir -p "$(dirname "$DOTFILES_DIR")"
        git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
    (cd "$DOTFILES_DIR" && git sparse-checkout disable 2>/dev/null || true)

    cd "$DOTFILES_DIR"
    source "$DOTFILES_DIR/install/common.sh"
    
    "$DOTFILES_DIR/install/install-cli.sh"
    "$DOTFILES_DIR/install/install-shell.sh"
    "$DOTFILES_DIR/install/install-nvim.sh" "--full"
    "$DOTFILES_DIR/install/install-vscode.sh" "--all"
    "$DOTFILES_DIR/install/install-mise.sh"
    "$DOTFILES_DIR/install/install-astral.sh"

    launch_shell "Full Workstation setup complete!"
fi

# ==========================================
# Option 2: Server / Minimal (Sparse-Checkout)
# ==========================================
if [[ "$CHOICE" == "2" || "$CHOICE" == "--server" || "$CHOICE" == "--minimal" ]]; then
    log "Setting up Server / Minimal environment via Git Sparse-Checkout..."
    
    DOTFILES_DIR="${HOME}/.dotfiles"
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        log "Cloning sparse repository to $DOTFILES_DIR..."
        git clone -b "$DOTFILES_BRANCH" --depth 1 --filter=blob:none --sparse "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
    cd "$DOTFILES_DIR"
    git sparse-checkout set nvim bin install starship
    source "$DOTFILES_DIR/install/common.sh"

    "$DOTFILES_DIR/install/install-cli.sh"
    "$DOTFILES_DIR/install/install-shell.sh"
    "$DOTFILES_DIR/install/install-nvim.sh" "--server"

    launch_shell "Server setup complete with Git sparse-checkout!"
fi

# ==========================================
# Option 3: Custom / Selective
# ==========================================
if [[ "$CHOICE" == "3" || "$CHOICE" == "--custom" || -z "$CHOICE" ]]; then
    log "Custom / Selective Installation Mode..."

    DOTFILES_DIR="${DOTFILES_DIR:-$DEFAULT_TARGET_DIR}"
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        log "Cloning dotfiles repository to $DOTFILES_DIR..."
        mkdir -p "$(dirname "$DOTFILES_DIR")"
        git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
    cd "$DOTFILES_DIR"
    source "$DOTFILES_DIR/install/common.sh"

    # Step 1: Core CLI Utilities Checklist
    echo ""
    cli_options=(
        "ripgrep (rg)    - Fast text search in files"
        "fd-find (fd)    - User-friendly, fast find replacement"
        "fzf             - General-purpose command-line fuzzy finder"
        "zoxide (z)      - Smarter cd directory jumper"
        "eza             - Modern ls with icons & git status"
        "starship        - Ultra-fast customizable shell prompt"
        "atuin           - Shell history with sync and fuzzy search"
        "genignore       - Smart gitignore generator"
    )
    cli_keys=(ripgrep fd fzf zoxide eza starship atuin genignore)
    cli_defs=(1 1 1 1 1 1 1 1)
    chosen_cli_indices=()
    multiselect "Step 1/2: Select Core CLI Utilities to install" cli_options cli_defs chosen_cli_indices

    # Map chosen CLI indices to tool names
    selected_cli_tools=()
    for idx in "${chosen_cli_indices[@]}"; do
        selected_cli_tools+=("${cli_keys[$idx]}")
    done

    # Step 2: Main Environments & Development Tools
    echo ""
    env_options=(
        "Zsh Shell & Config      - Portable .zshrc, .aliases & Oh My Zsh"
        "Neovim & Configuration   - Modern Lua setup, Lazy, Treesitter, LSP"
        "Visual Studio Code       - Settings, keybindings, snippets & extensions"
        "Mise & Node 24           - Polyglot runtime manager with Node 24"
        "Astral Python Tools      - uv package manager & ruff linter/formatter"
    )
    env_keys=(shell nvim vscode mise astral)
    env_defs=(1 1 1 1 1)
    chosen_env_indices=()
    multiselect "Step 2/2: Select Development Environments to install" env_options env_defs chosen_env_indices

    selected_envs=()
    for idx in "${chosen_env_indices[@]}"; do
        selected_envs+=("${env_keys[$idx]}")
    done

    # If Neovim was chosen, ask profile
    nvim_mode="--full"
    for env_item in "${selected_envs[@]}"; do
        if [ "$env_item" = "nvim" ]; then
            echo ""
            nvim_opts=(
                "Full Workstation  - Complete plugin suite (Treesitter, Telescope, Git, Markdown)"
                "Server / Minimal  - Lightweight configuration for headless servers"
            )
            nvim_defs=(1 0)
            chosen_nvim_idx=()
            multiselect "Select Neovim Profile:" nvim_opts nvim_defs chosen_nvim_idx
            if [ "${#chosen_nvim_idx[@]}" -gt 0 ] && [ "${chosen_nvim_idx[0]}" -eq 1 ]; then
                nvim_mode="--server"
            fi
            break
        fi
    done

    echo ""
    log "Beginning installation of selected components..."

    # Run selected CLI tools
    if [ "${#selected_cli_tools[@]}" -gt 0 ]; then
        "$DOTFILES_DIR/install/install-cli.sh" "${selected_cli_tools[@]}"
    fi

    # Run selected environments
    for env_item in "${selected_envs[@]}"; do
        case "$env_item" in
            shell)
                "$DOTFILES_DIR/install/install-shell.sh"
                ;;
            nvim)
                "$DOTFILES_DIR/install/install-nvim.sh" "$nvim_mode"
                ;;
            vscode)
                "$DOTFILES_DIR/install/install-vscode.sh"
                ;;
            mise)
                "$DOTFILES_DIR/install/install-mise.sh"
                ;;
            astral)
                "$DOTFILES_DIR/install/install-astral.sh"
                ;;
        esac
    done

    launch_shell "Selected dotfiles components installed successfully!"
fi
