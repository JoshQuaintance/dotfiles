#!/usr/bin/env bash
set -e

# Base dotfiles directory
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "$HOME/Codes/dotfiles")}"
export OS="$(uname -s)"

# Color helpers
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}=>${NC} $1"; }
success() { echo -e "${GREEN}✔${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✖${NC} $1"; }

# Ensure local bin directory exists in PATH
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Ensure Homebrew is loaded if on macOS
if [ "$OS" = "Darwin" ]; then
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# Function to check or install Homebrew on macOS
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

# Function to ensure git is installed across all platforms
ensure_git() {
    if ! command -v git &>/dev/null; then
        log "Git not found. Installing Git..."
        if [ "$OS" = "Darwin" ]; then
            ensure_homebrew
            brew install git
        elif [ "$OS" = "Linux" ]; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -y && sudo apt-get install -y git
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm git
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y git
            fi
        fi
        success "Git is installed!"
    fi
}
