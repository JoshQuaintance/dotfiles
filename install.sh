#!/usr/bin/env bash
set -e

# Disable Zsh builtin log command if running under Zsh
disable -r log 2>/dev/null || true

# Parse options (e.g. -b/--branch, -y/--yes, etc.)
CUSTOM_BRANCH_SPECIFIED=false
DRY_RUN=false
REMAINING_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--branch)
            if [ -n "$2" ]; then
                DOTFILES_BRANCH="$2"
                CUSTOM_BRANCH_SPECIFIED=true
                shift 2
            else
                shift
            fi
            ;;
        --branch=*)
            DOTFILES_BRANCH="${1#*=}"
            CUSTOM_BRANCH_SPECIFIED=true
            shift
            ;;
        -b=*)
            DOTFILES_BRANCH="${1#*=}"
            CUSTOM_BRANCH_SPECIFIED=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            REMAINING_ARGS+=("$1")
            shift
            ;;
    esac
done
if [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
    set -- "${REMAINING_ARGS[@]}"
else
    set --
fi

# Repository configuration
DOTFILES_REPO="https://github.com/JoshQuaintance/dotfiles.git"
DEFAULT_TARGET_DIR="$HOME/.dotfiles"

# Determine if running from a local clone or remotely via curl
CURRENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$CURRENT_SCRIPT_DIR/install/common.sh" ]; then
    DOTFILES_DIR="$CURRENT_SCRIPT_DIR"
    if [ "$CUSTOM_BRANCH_SPECIFIED" = false ] && [ -d "$CURRENT_SCRIPT_DIR/.git" ]; then
        DETECTED_BRANCH="$(git -C "$CURRENT_SCRIPT_DIR" branch --show-current 2>/dev/null || true)"
        [ -n "$DETECTED_BRANCH" ] && DOTFILES_BRANCH="$DETECTED_BRANCH"
    fi
else
    DOTFILES_DIR="$DEFAULT_TARGET_DIR"
fi

DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
RAW_BASE_URL="https://raw.githubusercontent.com/JoshQuaintance/dotfiles/${DOTFILES_BRANCH}"

# Load shared helpers from common.sh (locally if present, or dynamically via eval)
if [ -f "$DOTFILES_DIR/install/common.sh" ]; then
    source "$DOTFILES_DIR/install/common.sh"
else
    eval "$(curl -fsSL "$RAW_BASE_URL/install/common.sh")"
fi

# --dry-run: print every step (and which tools/links are missing) without changing anything
export DOTFILES_DRY_RUN="$DRY_RUN"

# Run an install step, or only describe it under --dry-run
run_step() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}would run:${NC} ${1#"$DOTFILES_DIR"/} ${*:2}"
        # install-cli.sh reports missing tools itself when DOTFILES_DRY_RUN=true
        [ "$(basename "$1")" = "install-cli.sh" ] && [ -f "$1" ] && "$@"
        return 0
    fi
    "$@"
}

# Clone (or reuse) the repo; under --dry-run only say what would happen
ensure_repo() {
    if [ -d "$DOTFILES_DIR/.git" ]; then
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}would clone:${NC} $DOTFILES_REPO ($DOTFILES_BRANCH) -> $DOTFILES_DIR"
        return 0
    fi
    log "Cloning dotfiles to $DOTFILES_DIR..."
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    git clone --single-branch --branch "$DOTFILES_BRANCH" --depth 1 "$@" "$DOTFILES_REPO" "$DOTFILES_DIR"
    git -C "$DOTFILES_DIR" config remote.origin.fetch "+refs/heads/$DOTFILES_BRANCH:refs/remotes/origin/$DOTFILES_BRANCH" 2>/dev/null || true
}

# Under --dry-run, list the config symlinks `dot link --fix` would create or repair, then stop
finish_dry_run() {
    echo ""
    if [ -f "$DOTFILES_DIR/cli/manifest.py" ] && command -v python3 &>/dev/null; then
        echo -e "${BLUE}Config links:${NC}"
        (cd "$DOTFILES_DIR" && python3 -c '
from pathlib import Path
from cli.manifest import get_dotfiles_dir, get_symlink_manifest
repo = get_dotfiles_dir()
for e in get_symlink_manifest():
    if not e.required and not e.link_path.parent.exists():
        continue
    target = (repo / e.rel_target).resolve()
    ok = e.link_path.is_symlink() and e.link_path.resolve() == target
    state = "ok" if ok else ("would back up & link" if e.link_path.exists() else "would link")
    mark = "✔" if ok else "+"
    shown = str(e.link_path).replace(str(Path.home()), "~")
    print(f"    {mark} {shown} ({state})")
')
    fi
    echo ""
    success "Dry run complete: nothing was changed."
    exit 0
}

# Ensure Git is installed and configure safe.directory
if [ "$DRY_RUN" = true ]; then
    command -v git &>/dev/null || echo -e "${BLUE}would install:${NC} git"
else
    ensure_git
    git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
    git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
fi

# Helper to read from /dev/tty if stdin is piped (e.g. curl ... | bash), portable for both Bash and Zsh
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

# Helper to launch into new shell automatically
launch_shell() {
    echo ""
    success "$1"
    if [ "${CI:-false}" = "true" ] || [ "${DOTFILES_NO_EXEC:-false}" = "true" ] || [ "${DOTFILES_UNATTENDED:-false}" = "true" ]; then
        return 0
    fi
    if [ ! -t 0 ] && { [ ! -e /dev/tty ] || [ ! -r /dev/tty ] || ! (true < /dev/tty) 2>/dev/null; }; then
        return 0
    fi
    if command -v zsh &>/dev/null; then
        log "Launching your new Zsh environment..."
        if [ -e /dev/tty ] && [ -r /dev/tty ] && (true < /dev/tty) 2>/dev/null; then
            exec zsh -l < /dev/tty
        elif [ -t 0 ]; then
            exec zsh -l
        fi
    fi
    exit 0
}

echo ""
echo "================================================="
echo "           Dotfiles Unified Installer            "
echo "           Branch: ${DOTFILES_BRANCH}            "
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
DOTFILES_UNATTENDED=false
if [[ "$CHOICE" == "-y" || "$CHOICE" == "--yes" || "$CHOICE" == "--unattended" ]]; then
    CHOICE="1"
    DOTFILES_UNATTENDED=true
    export DOTFILES_UNATTENDED
fi
if [ -z "$CHOICE" ]; then
    read_input "Select installation profile [1-3]: " CHOICE
fi

# ==========================================
# Option 1: Full Workstation
# ==========================================
if [[ "$CHOICE" == "1" || "$CHOICE" == "--workstation" || "$CHOICE" == "--all" ]]; then
    log "Setting up Full Workstation..."
    
    DOTFILES_DIR="${DOTFILES_DIR:-$DEFAULT_TARGET_DIR}"
    ensure_repo

    if [ "$DRY_RUN" != true ]; then
        git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
        (cd "$DOTFILES_DIR" && git sparse-checkout disable 2>/dev/null || true)
        cd "$DOTFILES_DIR"
        source "$DOTFILES_DIR/install/common.sh"
    fi

    run_step "$DOTFILES_DIR/install/install-cli.sh"
    run_step "$DOTFILES_DIR/install/install-shell.sh"

    # Interactive Editor Selection (default to all if unattended/piped)
    selected_editors=(nvim vscode)
    if [[ "$1" != "-y" && "$1" != "--yes" && "$1" != "--unattended" ]] && [ "$DRY_RUN" != true ] && [ -t 0 ] && [ -e /dev/tty ]; then
        echo ""
        # shellcheck disable=SC2034  # read by name in multiselect
        editor_opts=(
            "Neovim & Configuration   - Modern Lua setup, Lazy, Treesitter, LSP"
            "Visual Studio Code       - Settings, keybindings & snippets"
        )
        editor_keys=(nvim vscode)
        # shellcheck disable=SC2034  # read by name in multiselect
        editor_defs=(1 1)
        chosen_editor_idx=()
        multiselect "Select Editors to set up:" editor_opts editor_defs chosen_editor_idx
        selected_editors=()
        for idx in "${chosen_editor_idx[@]}"; do
            selected_editors+=("${editor_keys[$idx]}")
        done
    fi

    for ed in "${selected_editors[@]}"; do
        case "$ed" in
            nvim)   run_step "$DOTFILES_DIR/install/install-nvim.sh" "--full" ;;
            vscode) run_step "$DOTFILES_DIR/install/install-vscode.sh" ;;
        esac
    done

    run_step "$DOTFILES_DIR/install/install-mise.sh"
    if ! command -v mise &>/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
        run_step "$DOTFILES_DIR/install/install-nvm.sh"
    fi
    run_step "$DOTFILES_DIR/install/install-astral.sh"

    [ "$DRY_RUN" = true ] && finish_dry_run

    # Reconcile all declarative symlinks from cli/manifest.py
    "$DOTFILES_DIR/bin/dot" link --fix >/dev/null 2>&1 || true

    launch_shell "Full Workstation setup complete!"
fi

# ==========================================
# Option 2: Server / Minimal (Sparse-Checkout)
# ==========================================
if [[ "$CHOICE" == "2" || "$CHOICE" == "--server" || "$CHOICE" == "--minimal" ]]; then
    log "Setting up Server / Minimal environment via Git Sparse-Checkout..."
    
    DOTFILES_DIR="${HOME}/.dotfiles"
    ensure_repo --filter=blob:none --sparse

    SPARSE_PATHS=(config/nvim config/spaceship config/bat config/eza config/mise config/git config/atuin config/lazygit config/ssh zsh bin cli install)
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}would sparse-checkout:${NC} ${SPARSE_PATHS[*]}"
    else
        git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
        cd "$DOTFILES_DIR"
        git sparse-checkout set "${SPARSE_PATHS[@]}"
        source "$DOTFILES_DIR/install/common.sh"
    fi

    run_step "$DOTFILES_DIR/install/install-cli.sh"
    run_step "$DOTFILES_DIR/install/install-shell.sh"
    run_step "$DOTFILES_DIR/install/install-nvim.sh" "--server"
    [ "$DRY_RUN" = true ] && finish_dry_run

    launch_shell "Server setup complete with Git sparse-checkout!"
fi

# ==========================================
# Option 3: Custom / Selective
# ==========================================
if [[ "$CHOICE" == "3" || "$CHOICE" == "--custom" || -z "$CHOICE" ]]; then
    log "Custom / Selective Installation Mode..."

    DOTFILES_DIR="${DOTFILES_DIR:-$DEFAULT_TARGET_DIR}"
    ensure_repo

    if [ "$DRY_RUN" != true ]; then
        git config --global --add safe.directory "$DOTFILES_DIR" 2>/dev/null || true
        cd "$DOTFILES_DIR"
        source "$DOTFILES_DIR/install/common.sh"
    fi

    # Step 1: Core CLI Utilities Checklist
    echo ""
    cli_options=(
        "ripgrep (rg)    - Fast text search in files"
        "fd-find (fd)    - User-friendly, fast find replacement"
        "fzf             - General-purpose command-line fuzzy finder"
        "zoxide (z)      - Smarter cd directory jumper"
        "eza             - Modern ls with icons & git status"
        "bat             - Cat clone with syntax highlighting & Git status"
        "spaceship       - Native Zsh async shell prompt"
        "atuin           - Shell history with sync and fuzzy search"
        "yazi            - Blazingly fast terminal file manager"
        "dust            - Intuitive disk usage analyzer"
        "btop            - Modern resource & performance monitor"
        "git-delta       - Syntax-highlighting pager for git diffs"
        "lazygit         - Terminal UI for git"
        "glow            - Render Markdown in the terminal"
        "fzf-tab         - Interactive zsh completion menu"
        "genignore       - Smart gitignore generator"
    )
    cli_keys=(ripgrep fd fzf zoxide eza bat spaceship atuin yazi dust btop git-delta lazygit glow fzf-tab genignore)
    cli_defs=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)

    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        cli_options+=("WSL integration - win32yank clipboard & wslview browser opener")
        cli_keys+=(wsl)
        cli_defs+=(1)
    fi

    if [ "$OS" = "Darwin" ]; then
        cli_options+=(
            "Ghostty         - Fast GPU terminal emulator (macOS cask)"
            "Miracode Font   - Terminal & editor primary font (macOS cask)"
            "FiraCode NF     - Terminal fallback Nerd Font (macOS cask)"
            "Monocraft Font  - Pixel editor font (macOS cask)"
            "JetBrainsMono NF - Developer Nerd Font (macOS cask)"
        )
        cli_keys+=(ghostty font-miracode font-fira-code-nerd-font font-monocraft font-jetbrains-mono-nerd-font)
        cli_defs+=(1 1 1 1 1)
    else
        cli_options+=(
            "Developer Fonts - Miracode, FiraCode NF & Monocraft (Linux/WSL)"
        )
        cli_keys+=(fonts)
        cli_defs+=(1)
    fi

    chosen_cli_indices=()
    multiselect "Step 1/2: Select CLI & Terminal Components to install" cli_options cli_defs chosen_cli_indices

    # Map chosen CLI indices to tool names
    selected_cli_tools=()
    for idx in "${chosen_cli_indices[@]}"; do
        selected_cli_tools+=("${cli_keys[$idx]}")
    done

    # Step 2: Main Environments & Development Tools
    echo ""
    # shellcheck disable=SC2034  # read by name in multiselect
    env_options=(
        "Zsh Shell & Config      - Portable .zshrc, .aliases & Oh My Zsh"
        "Neovim & Configuration   - Modern Lua setup, Lazy, Treesitter, LSP"
        "Visual Studio Code       - Settings, keybindings & snippets"
        "Mise & Node LTS          - Polyglot runtime manager with Node LTS"
        "NVM (Node Version Mgr)   - Node version switcher fallback"
        "Astral Python Tools      - uv package manager & ruff linter/formatter"
    )
    env_keys=(shell nvim vscode mise nvm astral)
    # shellcheck disable=SC2034  # read by name in multiselect
    env_defs=(1 1 1 1 1 1)
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
            # shellcheck disable=SC2034  # read by name in multiselect
            nvim_opts=(
                "Full Workstation  - Complete plugin suite (Treesitter, Telescope, Git, Markdown)"
                "Server / Minimal  - Lightweight configuration for headless servers"
            )
            # shellcheck disable=SC2034  # read by name in multiselect
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
        run_step "$DOTFILES_DIR/install/install-cli.sh" "${selected_cli_tools[@]}"
    fi

    # Run selected environments
    for env_item in "${selected_envs[@]}"; do
        case "$env_item" in
            shell)
                run_step "$DOTFILES_DIR/install/install-shell.sh"
                ;;
            nvim)
                run_step "$DOTFILES_DIR/install/install-nvim.sh" "$nvim_mode"
                ;;
            vscode)
                run_step "$DOTFILES_DIR/install/install-vscode.sh"
                ;;
            mise)
                run_step "$DOTFILES_DIR/install/install-mise.sh"
                ;;
            nvm)
                run_step "$DOTFILES_DIR/install/install-nvm.sh"
                ;;
            astral)
                run_step "$DOTFILES_DIR/install/install-astral.sh"
                ;;
        esac
    done

    [ "$DRY_RUN" = true ] && finish_dry_run
    launch_shell "Selected dotfiles components installed successfully!"
fi
