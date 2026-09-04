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

# Interactive Multiselect Checklist in Pure Bash (Bash 3.2+ and Zsh compatible)
# Usage: multiselect "Prompt Title" "options_array_name" "defaults_array_name" "output_indices_array_name"
multiselect() {
    local prompt="$1"
    local opt_name="$2"
    local def_name="$3"
    local out_name="$4"

    local num_options=0
    eval "num_options=\${#${opt_name}[@]}"
    
    if [ "$num_options" -eq 0 ]; then
        return 0
    fi

    local cursor=0
    local selected=()
    local i

    # Populate selected array (1 = checked, 0 = unchecked)
    for ((i=0; i<num_options; i++)); do
        local def_val=1
        eval "def_val=\${${def_name}[$i]:-1}"
        selected[i]=$def_val
    done

    local tty_dev="/dev/tty"
    if [ ! -r /dev/tty ] || ! (true < /dev/tty) 2>/dev/null; then
        tty_dev="/dev/stdin"
    fi

    local old_stty
    old_stty=$(stty -g < "$tty_dev" 2>/dev/null || true)

    cleanup_multiselect() {
        [ -n "$old_stty" ] && stty "$old_stty" < "$tty_dev" 2>/dev/null || true
        printf "\033[?25h" # show cursor
    }
    trap cleanup_multiselect EXIT INT TERM

    # Hide cursor and enable raw input
    printf "\033[?25l"
    stty -echo -icanon min 1 time 0 < "$tty_dev" 2>/dev/null || true

    print_multiselect_menu() {
        echo -e "\033[1;36m$prompt\033[0m"
        echo -e "\033[2m  (Use ↑/↓ or j/k to navigate, Space to toggle, 'a' for all, Enter to confirm)\033[0m"
        for ((i=0; i<num_options; i++)); do
            local item_text=""
            eval "item_text=\"\${${opt_name}[$i]}\""
            
            local mark=" "
            [ "${selected[i]}" -eq 1 ] && mark="\033[1;32m✔\033[0m"

            if [ "$i" -eq "$cursor" ]; then
                echo -e " \033[1;34m❯\033[0m [$mark] \033[1;37m$item_text\033[0m"
            else
                echo -e "   [$mark] \033[0;37m$item_text\033[0m"
            fi
        done
    }

    clear_multiselect_menu() {
        local total_lines=$((num_options + 2))
        printf "\033[%dA" "$total_lines"
        for ((i=0; i<total_lines; i++)); do
            printf "\033[2K\r\n"
        done
        printf "\033[%dA" "$total_lines"
    }

    print_multiselect_menu

    while true; do
        local key=""
        local rest=""
        IFS= read -rsn1 key < "$tty_dev" 2>/dev/null || break

        if [ "$key" = $'\x1b' ]; then
            IFS= read -rsn2 -t 1 rest < "$tty_dev" 2>/dev/null || true
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A'|k|K) # Up
                if [ "$cursor" -gt 0 ]; then
                    cursor=$((cursor - 1))
                else
                    cursor=$((num_options - 1))
                fi
                ;;
            $'\x1b[B'|j|J) # Down
                if [ "$cursor" -lt $((num_options - 1)) ]; then
                    cursor=$((cursor + 1))
                else
                    cursor=0
                fi
                ;;
            " ") # Space (toggle)
                if [ "${selected[cursor]}" -eq 1 ]; then
                    selected[cursor]=0
                else
                    selected[cursor]=1
                fi
                ;;
            a|A) # Toggle all
                local any_unset=0
                for ((i=0; i<num_options; i++)); do
                    if [ "${selected[i]}" -eq 0 ]; then
                        any_unset=1
                        break
                    fi
                done
                for ((i=0; i<num_options; i++)); do
                    selected[i]=$any_unset
                done
                ;;
            ""|$'\n'|$'\r') # Enter
                break
                ;;
            $'\x03') # Ctrl+C
                cleanup_multiselect
                echo ""
                exit 1
                ;;
        esac

        clear_multiselect_menu
        print_multiselect_menu
    done

    cleanup_multiselect
    echo ""

    # Return array of selected indices
    local chosen=()
    for ((i=0; i<num_options; i++)); do
        if [ "${selected[i]}" -eq 1 ]; then
            chosen+=("$i")
        fi
    done
    eval "$out_name=(\"\${chosen[@]}\")"
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
