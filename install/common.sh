#!/usr/bin/env bash
set -e

# Disable Zsh builtin log command if running under Zsh
disable -r log 2>/dev/null || true

# Base dotfiles directory
export DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "$HOME/.dotfiles")}"
OS="$(uname -s)"
ARCH="$(uname -m)"
export OS ARCH

# Color helpers
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $*"; }
info() { echo -e "${BLUE}==>${NC} $*"; }
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
        # shellcheck disable=SC2229  # reads into the variable *named* by $var_name
        read -r "$var_name" < /dev/tty
    else
        # shellcheck disable=SC2229
        read -r "$var_name"
    fi
}

# Interactive Multiselect Checklist in Pure Bash (Bash 3.2+ and Zsh compatible)
# Usage: multiselect "Prompt Title" "options_array_name" "defaults_array_name" "output_indices_array_name"
multiselect() {
    [ -n "$ZSH_VERSION" ] && setopt LOCAL_OPTIONS KSH_ARRAYS 2>/dev/null || true
    disable -r log 2>/dev/null || true
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
    
    if [ "${DOTFILES_UNATTENDED:-false}" = "true" ] || [ "${CI:-false}" = "true" ]; then
        eval "$ans_var=false"
        return 0
    fi
    
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

# Ensure Homebrew environment on macOS & Linux/WSL
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Function to ensure Homebrew on macOS
ensure_homebrew() {
    if [ "$OS" = "Darwin" ]; then
        if ! command -v brew &>/dev/null; then
            log "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [ -f "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -f "/usr/local/bin/brew" ]; then
                eval "$(/usr/local/bin/brew shellenv)"
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

# Universal single-branch shallow clone helper
# Usage: git_clone_single <repo_url> <target_dir> [branch] [extra_git_args...]
git_clone_single() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="${3:-main}"
    shift 3 || true
    log "Cloning $repo_url (single-branch: $branch)..."
    git clone --single-branch --branch "$branch" --depth 1 "$@" "$repo_url" "$target_dir"
    git -C "$target_dir" config remote.origin.fetch "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null || true
}

# Run a build or install command inside a temporary git clone and automatically clean it up
# Usage: git_clone_and_clean <repo_url> <branch> <command_to_run_inside_repo>
git_clone_and_clean() {
    local repo_url="$1"
    local branch="${2:-main}"
    local build_cmd="$3"
    local tmp_repo
    tmp_repo="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-build.XXXXXX")"
    log "Cloning $repo_url (single-branch: $branch) to temporary directory..."
    if git clone --single-branch --branch "$branch" --depth 1 "$repo_url" "$tmp_repo"; then
        (
            cd "$tmp_repo"
            eval "$build_cmd"
        )
        local status=$?
        rm -rf "$tmp_repo"
        log "Cleaned up temporary repository."
        return $status
    else
        rm -rf "$tmp_repo"
        error "Failed to clone $repo_url"
        return 1
    fi
}

# Declarative symlink helper with automatic parent creation and collision backup
# Usage: link_dotfile <repo_rel_path> <dest_link_path>
link_dotfile() {
    local src="$DOTFILES_DIR/$1"
    local dest="$2"
    [ -e "$src" ] || return 0

    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$(readlink "$dest" 2>/dev/null)" != "$src" ]; then
            local bak="${dest}.bak"
            [ -e "$bak" ] && bak="${dest}.bak.$(date +%Y%m%d%H%M%S)"
            mv "$dest" "$bak" 2>/dev/null || cp -LR "$dest" "$bak" 2>/dev/null || true
        fi
    fi
    ln -sfn "$src" "$dest"
    success "Linked ${dest/#$HOME/\~} -> $1"
}

# ==============================================================================
# Parallel Step Execution Engine (Multi-Process Fan-Out)
# Supports concurrent background workers with isolated logs, live progress updates,
# and safe resource throttling for mobile/PRoot/low-RAM environments.
#
# Usage:
#   labels=("Neovim" "Mise" "Astral")
#   cmds=("$DOTFILES_DIR/install/install-nvim.sh --full" "$DOTFILES_DIR/install/install-mise.sh" "$DOTFILES_DIR/install/install-astral.sh")
#   run_parallel_steps "Development Environments" labels cmds
# ==============================================================================
run_parallel_steps() {
    [ -n "$ZSH_VERSION" ] && setopt LOCAL_OPTIONS KSH_ARRAYS 2>/dev/null || true
    disable -r log 2>/dev/null || true
    local title="$1"
    local labels_var="$2"
    local cmds_var="$3"

    local total=0
    eval "total=\${#${labels_var}[@]}"
    [ "$total" -eq 0 ] && return 0

    if [ "${DOTFILES_DRY_RUN:-false}" = true ]; then
        echo -e "${BLUE}would run in parallel ($title):${NC}"
        local i
        for ((i=0; i<total; i++)); do
            local lbl cmd
            eval "lbl=\"\${${labels_var}[$i]}\""
            eval "cmd=\"\${${cmds_var}[$i]}\""
            echo -e "  ${BLUE}•${NC} $lbl: $cmd"
        done
        return 0
    fi

    if [ "${DOTFILES_SERIAL:-false}" = true ] || [ "$total" -le 1 ]; then
        local i
        for ((i=0; i<total; i++)); do
            local cmd
            eval "cmd=\"\${${cmds_var}[$i]}\""
            run_step eval "$cmd"
        done
        return 0
    fi

    local max_concurrency=4
    if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ] || [ -n "${PROOT_TMP_DIR:-}" ]; then
        max_concurrency=2
    elif [ -f /proc/version ] && grep -qiE '(android|samsung|qcom)' /proc/version 2>/dev/null; then
        max_concurrency=2
    elif [ -n "$(uname -r 2>/dev/null | grep -iE 'android')" ]; then
        max_concurrency=2
    fi

    echo ""
    log "Provisioning $title in parallel (max $max_concurrency workers)..."

    local log_dir="${TMPDIR:-/tmp}/dotfiles-parallel-$$"
    mkdir -p "$log_dir"

    local job_pids=()
    local job_labels=()
    local job_logs=()
    local job_starts=()
    local failed_indices=()
    local next_idx=0
    local running=0
    local completed=0
    local i=0
    local j=0
    local idx=0
    local pid=0
    local exit_code=0
    local start=0
    local dur=0
    local f_idx=0
    local lbl=""
    local cmd=""
    local log_file=""

    local spinners=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spin_idx=0

    cleanup_parallel_workers() {
        local k=0
        local p=0
        for ((k=0; k<next_idx; k++)); do
            p="${job_pids[k]:-0}"
            [ "$p" -gt 0 ] && kill -TERM "$p" 2>/dev/null || true
        done
        rm -rf "$log_dir" 2>/dev/null || true
        exit 130
    }
    trap cleanup_parallel_workers INT TERM

    while [ "$completed" -lt "$total" ]; do
        # Spawn queued jobs up to max_concurrency
        while [ "$running" -lt "$max_concurrency" ] && [ "$next_idx" -lt "$total" ]; do
            idx="$next_idx"
            eval "lbl=\"\${${labels_var}[$idx]}\""
            eval "cmd=\"\${${cmds_var}[$idx]}\""
            log_file="$log_dir/task_${idx}.log"

            ( export DOTFILES_UNATTENDED=true; eval "$cmd" ) > "$log_file" 2>&1 &
            pid=$!

            job_pids[idx]=$pid
            job_labels[idx]="$lbl"
            job_logs[idx]="$log_file"
            job_starts[idx]=$(date +%s)

            running=$((running + 1))
            next_idx=$((next_idx + 1))
        done

        # Check running jobs
        for ((j=0; j<next_idx; j++)); do
            pid="${job_pids[j]:-0}"
            if [ "$pid" -gt 0 ]; then
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid"
                    exit_code=$?
                    start="${job_starts[j]}"
                    dur=$(( $(date +%s) - start ))

                    if [ "$exit_code" -eq 0 ]; then
                        printf "\r\033[K  ${GREEN}✔${NC} %-36s ${GREEN}(done in %ds)${NC}\n" "${job_labels[j]}" "$dur"
                    else
                        printf "\r\033[K  ${RED}✖${NC} %-36s ${RED}(failed with exit %d after %ds)${NC}\n" "${job_labels[j]}" "$exit_code" "$dur"
                        failed_indices+=("$j")
                    fi

                    job_pids[j]=0
                    running=$((running - 1))
                    completed=$((completed + 1))
                fi
            fi
        done

        if [ "$completed" -lt "$total" ]; then
            if [ -t 1 ]; then
                printf "\r  ${YELLOW}%s${NC} [%d/%d completed] Running %d background worker(s)..." "${spinners[spin_idx]}" "$completed" "$total" "$running"
                spin_idx=$(( (spin_idx + 1) % 10 ))
            fi
            sleep 0.2
        fi
    done

    printf "\r\033[K"
    trap - INT TERM

    if [ "${#failed_indices[@]}" -gt 0 ]; then
        echo ""
        error "The following $title step(s) encountered errors:"
        for f_idx in "${failed_indices[@]}"; do
            echo -e "\n${RED}--- Log for ${job_labels[f_idx]} (${job_logs[f_idx]}) ---${NC}"
            tail -n 25 "${job_logs[f_idx]}" 2>/dev/null || true
        done
        rm -rf "$log_dir" 2>/dev/null || true
        return 1
    fi

    success "All $title steps completed successfully!"
    rm -rf "$log_dir" 2>/dev/null || true
    return 0
}
