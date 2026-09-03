#!/usr/bin/env bash
set -e

# Disable Zsh builtin log command if running under Zsh
disable -r log 2>/dev/null || true

# Repository configuration
DOTFILES_REPO="https://github.com/JoshQuaintance/dotfiles.git"
RAW_BASE_URL="https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main"
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
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
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
        git clone --depth 1 --filter=blob:none --sparse "$DOTFILES_REPO" "$DOTFILES_DIR"
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
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
    cd "$DOTFILES_DIR"
    source "$DOTFILES_DIR/install/common.sh"

    read_input "Install Core CLI Utilities (ripgrep, fd, fzf, zoxide, genignore)? [y/N]: " a_cli
    read_input "Install & Configure Zsh Shell (.zshrc & Oh My Zsh)? [y/N]: " a_shell

    read_input "Install Neovim & Configuration? [y/N]: " a_nvim
    if [[ "$a_nvim" =~ ^[Yy]$ ]]; then
        read_input "  Use (f)ull plugins or (s)erver minimal? [f/s]: " n_ans
    fi

    read_input "Install VSCode settings & extensions? [y/N]: " a_vsc
    read_input "Install Mise & Node 24? [y/N]: " a_mise
    read_input "Install Astral Python Tools (uv & ruff)? [y/N]: " a_astral

    # Run selected module installers
    [[ "$a_cli" =~ ^[Yy]$ ]] && "$DOTFILES_DIR/install/install-cli.sh"
    [[ "$a_shell" =~ ^[Yy]$ ]] && "$DOTFILES_DIR/install/install-shell.sh"
    if [[ "$a_nvim" =~ ^[Yy]$ ]]; then
        [[ "$n_ans" =~ ^[Ss]$ ]] && "$DOTFILES_DIR/install/install-nvim.sh" "--server" || "$DOTFILES_DIR/install/install-nvim.sh" "--full"
    fi
    [[ "$a_vsc" =~ ^[Yy]$ ]] && "$DOTFILES_DIR/install/install-vscode.sh"
    [[ "$a_mise" =~ ^[Yy]$ ]] && "$DOTFILES_DIR/install/install-mise.sh"
    [[ "$a_astral" =~ ^[Yy]$ ]] && "$DOTFILES_DIR/install/install-astral.sh"

    launch_shell "Selected dotfiles components installed successfully!"
fi
