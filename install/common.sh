#!/usr/bin/env bash
set -e

# Disable Zsh builtin log command if running under Zsh
disable -r log 2>/dev/null || true

# Base dotfiles directory
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "$HOME/Codes/dotfiles")}"
export OS="$(uname -s)"
export ARCH="$(uname -m)"

# Color helpers
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✖${NC} $*"; }

# Universal sudo wrapper (runs directly if root, uses sudo if available)
run_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        "$@"
    fi
}

# Portable read_input compatible with both Bash and Zsh
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

# Helper to ask whether to update an already installed tool (defaults to Yes/Update)
ask_update_tool() {
    local tool_name="$1"
    local version_info="$2"
    local ans_var="$3"
    
    local prompt_msg="  [?] $tool_name"
    if [ -n "$version_info" ]; then
        prompt_msg="$prompt_msg ($version_info)"
    fi
    prompt_msg="$prompt_msg is already installed. Update to latest? [Y/n]: "
    
    local user_ans=""
    read_input "$prompt_msg" user_ans
    if [[ "$user_ans" =~ ^[Nn]$ ]]; then
        eval "$ans_var=false"
    else
        eval "$ans_var=true"
    fi
}

# Ensure local bin directory exists in PATH
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Ensure Homebrew environment on macOS
if [ "$OS" = "Darwin" ]; then
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# Function to ensure Homebrew on macOS
ensure_homebrew() {
    if [ "$OS" = "Darwin" ]; then
        if ! command -v brew &>/dev/null; then
            log "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [ -f "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
    fi
}

# Function to ensure base system build & download dependencies
ensure_base_deps() {
    if [ "$OS" = "Darwin" ]; then
        ensure_homebrew
        if ! command -v git &>/dev/null; then
            brew install git
        fi
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            # Ubuntu / Debian
            run_sudo apt-get update -y
            run_sudo apt-get install -y curl wget git build-essential ca-certificates tar gzip unzip
        elif command -v dnf &>/dev/null; then
            # Fedora
            run_sudo dnf install -y curl wget git make gcc ca-certificates tar gzip unzip
        elif command -v pacman &>/dev/null; then
            # Arch Linux
            run_sudo pacman -S --noconfirm --needed curl wget git base-devel ca-certificates tar gzip unzip
        fi
    fi
}

# Ensure git is available and mark directory safe for containers
ensure_git() {
    if ! command -v git &>/dev/null; then
        ensure_base_deps
    fi
    git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
    git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
}
