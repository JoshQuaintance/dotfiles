#!/usr/bin/env bash
set -e

# Dotfiles Python & uv Environment Bootstrapper
# Ensures an isolated ~/.dotfiles/.venv exists with zero contamination of system Python

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$DOTFILES_DIR/.venv"

# Ensure local user paths are in PATH
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

if [ -f "$VENV_DIR/bin/python" ] && "$VENV_DIR/bin/python" -c "import sys; sys.exit(0)" 2>/dev/null; then
    exit 0
fi

printf "\033[1;34m==>\033[0m Initializing isolated Python environment for dotfiles tooling...\n"

# 1. Check for uv or install it
ensure_uv() {
    if command -v uv &>/dev/null; then
        return 0
    fi

    # Check if Homebrew has it on macOS
    if command -v brew &>/dev/null; then
        brew install uv 2>/dev/null && return 0 || true
    fi

    # Standalone official Astral installer
    if command -v curl &>/dev/null; then
        printf "  Installing uv (Astral fast Python runner)...\n"
        curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null || true
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        command -v uv &>/dev/null && return 0
    fi

    return 1
}

# 2. Check for Python runtime if uv cannot manage it or is absent
ensure_system_python() {
    if command -v python3 &>/dev/null; then
        return 0
    fi

    printf "\033[1;33m⚠ Python 3 not detected. Installing Python runtime...\033[0m\n"
    if [ "$(uname -s)" = "Darwin" ]; then
        if command -v brew &>/dev/null; then
            brew install python3
        fi
    elif [ "$(uname -s)" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            if [ "$(id -u)" -eq 0 ]; then
                apt-get update -y && apt-get install -y python3 python3-venv python3-pip curl
            elif command -v sudo &>/dev/null; then
                sudo apt-get update -y && sudo apt-get install -y python3 python3-venv python3-pip curl
            fi
        elif command -v dnf &>/dev/null; then
            if [ "$(id -u)" -eq 0 ]; then
                dnf install -y python3 python3-pip curl
            elif command -v sudo &>/dev/null; then
                sudo dnf install -y python3 python3-pip curl
            fi
        elif command -v pacman &>/dev/null; then
            if [ "$(id -u)" -eq 0 ]; then
                pacman -S --noconfirm python python-pip curl
            elif command -v sudo &>/dev/null; then
                sudo pacman -S --noconfirm python python-pip curl
            fi
        fi
    fi
}

ensure_system_python || true
ensure_uv || true

# 3. Create the isolated virtual environment
mkdir -p "$DOTFILES_DIR"

if command -v uv &>/dev/null; then
    printf "  Creating virtual environment via uv...\n"
    uv venv "$VENV_DIR" --quiet 2>/dev/null || uv venv "$VENV_DIR"
    printf "  Installing terminal UI dependencies into .venv...\n"
    uv pip install --python "$VENV_DIR/bin/python" "rich>=13.0.0" --quiet 2>/dev/null || true
elif command -v python3 &>/dev/null; then
    printf "  Creating virtual environment via python3 -m venv...\n"
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --quiet "rich>=13.0.0" 2>/dev/null || true
else
    printf "\033[31m✖ Error: Failed to bootstrap Python environment. Please install Python 3 or uv.\033[0m\n" >&2
    exit 1
fi

if [ -f "$VENV_DIR/bin/python" ]; then
    printf "\033[32m✔\033[0m Dotfiles Python environment ready at \033[1m%s\033[0m\n" "$VENV_DIR"
fi
