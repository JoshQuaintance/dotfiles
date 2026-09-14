# Startup verbose checklist & environment banner
if [[ -o interactive ]] && [ -t 1 ] && [ "${ZSH_STARTUP_VERBOSE:-true}" = true ]; then
    _ZSH_STARTUP_VERBOSE=true
    [ -z "$LANG" ] && [ -z "$LC_ALL" ] && export LANG="en_US.UTF-8"
    zmodload zsh/datetime 2>/dev/null || true
    _t_start=$EPOCHREALTIME
    _t_step=$_t_start

    # Theme palette (configurable via ZSH_BANNER_THEME: cyan, catppuccin, tokyonight, nord, matrix, monochrome)
    case "${ZSH_BANNER_THEME:-cyan}" in
        catppuccin|mauve)
            _c_border="\033[38;2;203;166;247m"
            _c_check="\033[38;2;166;227;161m"
            _c_title="\033[1;38;2;245;194;231m"
            _c_key="\033[1;38;2;137;180;250m"
            ;;
        tokyonight|blue)
            _c_border="\033[38;2;122;162;247m"
            _c_check="\033[38;2;115;218;202m"
            _c_title="\033[1;38;2;187;154;247m"
            _c_key="\033[1;38;2;125;207;255m"
            ;;
        nord)
            _c_border="\033[38;2;136;192;208m"
            _c_check="\033[38;2;163;190;140m"
            _c_title="\033[1;38;2;129;161;193m"
            _c_key="\033[1;38;2;236;239;244m"
            ;;
        matrix|green)
            _c_border="\033[1;32m"
            _c_check="\033[1;32m"
            _c_title="\033[1;32m"
            _c_key="\033[32m"
            ;;
        monochrome|minimal)
            _c_border="\033[2m"
            _c_check="\033[1m"
            _c_title="\033[1m"
            _c_key="\033[1m"
            ;;
        *) # cyan / default
            _c_border="\033[1;36m"
            _c_check="\033[1;32m"
            _c_title="\033[1;36m"
            _c_key="\033[1m"
            ;;
    esac
    _c_reset="\033[0m"
    _c_dim="\033[2m"

    _step() {
        if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
            local t_now=$EPOCHREALTIME
            local elapsed=$(( (t_now - _t_step) * 1000 ))
            _t_step=$t_now
            printf "${_c_border}│${_c_reset}  ${_c_check}✔${_c_reset} %-41s ${_c_dim}%5.0fms${_c_reset} ${_c_border}│${_c_reset}\n" "$1" "$elapsed"
        fi
    }

    if [ "$(uname -s)" = "Darwin" ]; then
        _os_logo=""
        _logo_extra=0
    else
        _os_logo="🐧"
        _logo_extra=1
    fi
    _raw_title="${ZSH_BANNER_TITLE:-$(whoami)@$(hostname -s)}"
    _title="${_os_logo} ${_raw_title}"
    _pad_top=$(( 51 - ${#_title} - _logo_extra ))
    printf "${_c_border}╭─ ${_c_title}%s${_c_reset}${_c_border} %s╮${_c_reset}\n" "$_title" "$(printf "─%.0s" {1..$_pad_top})"
else
    _ZSH_STARTUP_VERBOSE=false
    _step() { :; }
fi

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Homebrew environment (macOS Apple Silicon & Linuxbrew)
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export C_INCLUDE_PATH="/opt/homebrew/include:$C_INCLUDE_PATH"
    export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"
elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Optional Homebrew tool paths (if installed)
[ -d "/opt/homebrew/opt/openjdk@21/bin" ] && export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
[ -d "/opt/homebrew/opt/python@3.14/bin" ] && export PATH="/opt/homebrew/opt/python@3.14/bin:$PATH"
_step "Homebrew environment"

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder
zstyle ':omz:plugins:eza' 'icons' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'hyperlink' yes

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git eza starship)

# Compile ~/.zcompdump to bytecode ~/.zcompdump.zwc for instant load
if [ -f "$HOME/.zcompdump" ] && [ ! -f "$HOME/.zcompdump.zwc" -o "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ]; then
    zcompile "$HOME/.zcompdump" 2>/dev/null || true
fi

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
else
    # Fallback Git prompt if Oh My Zsh is not yet installed
    autoload -Uz vcs_info
    precmd() { vcs_info }
    zstyle ':vcs_info:git:*' formats ' (%b)'
    setopt PROMPT_SUBST
    PROMPT='%F{cyan}%~%F{yellow}${vcs_info_msg_0_}%F{reset} %# '
fi
_step "Oh My Zsh & plugins (git, eza)"

# Starship Prompt Initialization
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi
_step "Starship prompt"

# ==========================================
# User Configuration & Tools
# ==========================================

# Mise (Polyglot Runtime & Node 24 Manager)
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh)"
fi
_step "Mise polyglot runtime"

# NVM (Lazy-loaded fallback — saves ~800-1200ms on startup)
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    nvm() {
        unset -f nvm node npm npx yarn 2>/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm "$@"
    }
fi

# Astral Python Tools (uv & ruff completions, cached)
if command -v uv &>/dev/null; then
    _uv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/uv_completion.zsh"
    [ ! -s "$_uv_cache" ] && mkdir -p "$(dirname "$_uv_cache")" && (uv generate-shell-completion zsh > "$_uv_cache" 2>/dev/null || rm -f "$_uv_cache")
    [ -s "$_uv_cache" ] && source "$_uv_cache"
fi
if command -v ruff &>/dev/null; then
    _ruff_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ruff_completion.zsh"
    [ ! -s "$_ruff_cache" ] && mkdir -p "$(dirname "$_ruff_cache")" && (ruff generate-shell-completion zsh > "$_ruff_cache" 2>/dev/null || rm -f "$_ruff_cache")
    [ -s "$_ruff_cache" ] && source "$_ruff_cache"
fi

# Angular CLI autocompletion (cached to prevent spawning node on every launch)
if command -v ng &>/dev/null; then
    _ng_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ng_completion.zsh"
    if [ ! -s "$_ng_cache" ]; then
        mkdir -p "$(dirname "$_ng_cache")"
        ng completion script > "$_ng_cache" 2>/dev/null || rm -f "$_ng_cache"
    fi
    [ -s "$_ng_cache" ] && source "$_ng_cache"
fi

export BASE="$HOME/Codes"
[ -d "$HOME/Codes/sentinel-service/bin" ] && export PATH="$HOME/Codes/sentinel-service/bin:$PATH"

export STL_VAULT_PROD_ADDR="https://vault.winsupply.com"
export STL_VAULT_DEV_ADDR="https://vault-test.winsupply.com"
_step "Completions & SDK paths"

# Bun
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# PNPM
if [ -d "$HOME/Library/pnpm" ]; then
    export PNPM_HOME="$HOME/Library/pnpm"
    export PATH="$PNPM_HOME/bin:$PATH"
elif [ -d "$HOME/.local/share/pnpm" ]; then
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME/bin:$PATH"
fi

# Atuin (Shell History)
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# Zoxide (Smart directory jumper: 'z <folder>')
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# FZF (Fuzzy finder integration)
if command -v fzf &>/dev/null; then
    [ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"
    source <(fzf --zsh 2>/dev/null) 2>/dev/null || true
fi

# Preferred editor for local and remote sessions
export EDITOR='nvim'
export VISUAL='nvim'
_step "CLI tools (Atuin, Zoxide, FZF, Bun)"

# ==========================================
# Aliases & Shortcuts
# ==========================================
[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -f "$DOTFILES_DIR/.aliases" ] && [ ! -f "$HOME/.aliases" ] && source "$DOTFILES_DIR/.aliases"
_step "Dotfiles aliases & script runners"

# Startup Summary Card
if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
    _t_total=$(( EPOCHREALTIME - _t_start ))
    _tot_str=$(printf "%.2fs" "$_t_total")
    _arch="$(uname -m)"
    _os_name="$(uname -s)"
    _node_ver=$(node -v 2>/dev/null || echo "N/A")
    _bun_ver=$(bun -v 2>/dev/null || echo "N/A")

    if [ "$_os_name" = "Darwin" ]; then
        _os_str="macOS (${_arch})"
    else
        _os_str="${_os_name} (${_arch})"
    fi

    # 1. Dotfiles info (branch & short commit)
    _dot_dir="${DOTFILES_DIR:-$HOME/Codes/dotfiles}"
    _dot_branch="$(git -C "$_dot_dir" branch --show-current 2>/dev/null || echo "main")"
    _dot_hash="$(git -C "$_dot_dir" rev-parse --short HEAD 2>/dev/null || echo "")"
    _dot_info="${_dot_branch}${_dot_hash:+ (${_dot_hash})}"

    # 2. Battery status (macOS pmset + Linux sysfs /sys/class/power_supply)
    _batt_info=""
    _batt_extra=0
    _batt_label="Battery:"
    if command -v pmset &>/dev/null; then
        # macOS
        _batt_raw="$(pmset -g batt 2>/dev/null)"
        _batt_pct="$(echo "$_batt_raw" | grep -Eo '[0-9]+%' | head -n 1)"
        if [ -n "$_batt_pct" ]; then
            if echo "$_batt_raw" | grep -qi "charging" && ! echo "$_batt_raw" | grep -qi "not charging"; then
                _batt_info="${_batt_pct} ⚡"
            else
                _batt_info="${_batt_pct} 🔋"
            fi
            _batt_extra=1
        fi
    elif [ -d /sys/class/power_supply ]; then
        # Linux laptops
        for _bat in /sys/class/power_supply/BAT* /sys/class/power_supply/battery; do
            if [ -f "$_bat/capacity" ]; then
                _pct="$(cat "$_bat/capacity" 2>/dev/null)%"
                _st="$(cat "$_bat/status" 2>/dev/null)"
                if [ "$_st" = "Charging" ]; then
                    _batt_info="${_pct} ⚡"
                elif [ "$_st" = "Full" ]; then
                    _batt_info="${_pct} 🔌"
                else
                    _batt_info="${_pct} 🔋"
                fi
                _batt_extra=1
                break
            fi
        done
    fi

    if [ -z "$_batt_info" ]; then
        _batt_label="Network:"
        _batt_info="Online"
        _batt_extra=0
    fi

    # 3. System Uptime (macOS sysctl + Linux /proc/uptime)
    _uptime_str="N/A"
    _up_sec=0
    if [ "$_os_name" = "Darwin" ]; then
        _boot_sec="$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')"
        [ -n "$_boot_sec" ] && _up_sec=$(( EPOCHSECONDS - _boot_sec ))
    elif [ -f /proc/uptime ]; then
        _up_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
    fi

    if [ -n "$_up_sec" ] && [ "$_up_sec" -gt 0 ]; then
        _up_d=$(( _up_sec / 86400 ))
        _up_h=$(( (_up_sec % 86400) / 3600 ))
        _up_m=$(( (_up_sec % 3600) / 60 ))
        if [ "$_up_d" -gt 0 ]; then
            _uptime_str="${_up_d}d ${_up_h}h"
        elif [ "$_up_h" -gt 0 ]; then
            _uptime_str="${_up_h}h ${_up_m}m"
        else
            _uptime_str="${_up_m}m"
        fi
    fi

    # 4. CPU Load & Memory Stats (macOS vm_stat + Linux /proc)
    _cpu_load=""
    _mem_str="N/A"
    if [ "$_os_name" = "Darwin" ]; then
        _cpu_load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
        if command -v vm_stat &>/dev/null; then
            _tot_ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
            _mem_str="$(vm_stat | awk -v tot="$_tot_ram" '
                /page size of/ { ps = substr($8, 1, length($8)) + 0 }
                /Pages active:/ { a = substr($3, 1, length($3)-1) + 0 }
                /Pages wired/ { w = substr($4, 1, length($4)-1) + 0 }
                /occupied by compressor:/ { c = substr($5, 1, length($5)-1) + 0 }
                END {
                    if (ps == 0) ps = 16384;
                    used = (a + w + c) * ps / (1024*1024*1024);
                    printf "%.0f/%.0fGB", used, tot;
                }
            ')"
        fi
    else
        [ -f /proc/loadavg ] && _cpu_load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
        if [ -f /proc/meminfo ]; then
            _mem_str="$(awk '/MemTotal:/ {tot=$2} /MemAvailable:/ {avail=$2} END { used=(tot-avail)/1048576; tot_gb=tot/1048576; printf "%.0f/%.0fGB", used, tot_gb }' /proc/meminfo 2>/dev/null)"
        fi
    fi

    # 5. Disk Space
    _disk_str="$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s (%s)", $4, $5}')"

    # 6. Rotating Shortcuts / Tips
    _tips=(
        "'npmr' / 'bunr'   → Interactive script runner"
        "'dotcheck'        → Check for dotfiles updates"
        "'groot'           → Jump to git project root"
        "'killport <port>' → Kill process on port"
        "'esdiff'          → ESLint changed .ts files"
        "'conf <target>'   → Edit config & auto-reload"
        "'gprune'          → Prune remote git branches"
        "'gbclean'         → Delete merged git branches"
        "'take <dir>'      → mkdir -p and cd in one step"
        "'sz'              → Reload ~/.zshrc and aliases"
        "'port <port>'     → Show process on port"
    )
    _random_tip="${_tips[$(( (RANDOM % ${#_tips[@]}) + 1 ))]}"

    # Formatting helpers for exact column alignment
    vpad() {
        local val="$1"
        local target_w="$2"
        local extra_w="${3:-0}"
        local val_len=$(( ${#val} + extra_w ))
        local pad_len=$(( target_w - val_len ))
        local spaces=""
        if [ "$pad_len" -gt 0 ]; then
            spaces=$(printf "%*s" "$pad_len" "")
        fi
        printf "%s%s" "$val" "$spaces"
    }

    grid_row() {
        local k1="$1" v1="$2" k2="$3" v2="$4" extra1="${5:-0}" extra2="${6:-0}"
        local p_v1="$(vpad "$v1" 15 "$extra1")"
        local p_v2="$(vpad "$v2" 15 "$extra2")"
        printf "${_c_border}│${_c_reset}  ${_c_key}%-9s${_c_reset}%s${_c_border}│${_c_reset}  ${_c_key}%-10s${_c_reset}%s${_c_border}│${_c_reset}\n" \
            "$k1" "$p_v1" "$k2" "$p_v2"
    }

    printf "${_c_border}├%s┬%s┤${_c_reset}\n" "$(printf "─%.0s" {1..26})" "$(printf "─%.0s" {1..27})"
    grid_row "System:"       "$_os_str"                         "Dotfiles:" "$_dot_info"
    grid_row "Uptime:"       "$_uptime_str"                     "Node:"     "$_node_ver"
    grid_row "CPU/RAM:"      "${_cpu_load:-N/A} / ${_mem_str}"  "Bun:"      "$_bun_ver"
    grid_row "Disk:"         "${_disk_str:-N/A}"                "$_batt_label" "$_batt_info" 0 "$_batt_extra"
    grid_row "Shell:"        "zsh ${ZSH_VERSION:-5.9}"          "Ready in:" "$_tot_str"
    printf "${_c_border}├%s┴%s┤${_c_reset}\n" "$(printf "─%.0s" {1..26})" "$(printf "─%.0s" {1..27})"

    # Rotating Tip Line
    _tip_line="💡 ${_random_tip}"
    _pad_tip=$(( 51 - ${#_tip_line} ))
    _spaces_tip=""
    if [ "$_pad_tip" -gt 0 ]; then
        _spaces_tip=$(printf "%*s" "$_pad_tip" "")
    fi
    printf "${_c_border}│${_c_reset}  ${_c_dim}%s%s${_c_reset}${_c_border}│${_c_reset}\n" "$_tip_line" "$_spaces_tip"

    printf "${_c_border}╰%s╯${_c_reset}\n" "$(printf "─%.0s" {1..54})"
    echo ""
fi

# ==========================================
# Custom Functions
# ==========================================

# ESLint changed .ts files vs origin/develop
esdiff() {
  local files
  files=($(git diff origin/develop...HEAD --name-only --diff-filter=d | grep '\.ts$'))
  if (( $#files == 0 )); then
    echo "No .ts files changed vs origin/develop"
    return 0
  fi
  echo "Checking $#files file(s):"
  printf '  %s\n' $files
  npx eslint $files
}

# Run specific acceptance test
acceptance() {
  local test=$1
  echo "Running test \"$test\""
  npm run test:acceptance:refactored -- --grep "$test"
}

# Quick git clone helper: clone <org/repo>
clone() {
  local repo=$1
  echo "Cloning $repo - git clone git@github.com:$repo.git"
  git clone git@github.com:$repo.git
}

# Edit configurations and reload automatically only if modified
conf() {
  local target="${1:-shell}"
  local target_file=""
  local is_shell_rc=false

  case "$target" in
    shell|"")
      if [ -n "$ZSH_VERSION" ]; then
        target_file="$HOME/.zshrc"
      elif [ -n "$BASH_VERSION" ]; then
        target_file="$HOME/.bashrc"
      else
        target_file="$HOME/.zshrc"
      fi
      is_shell_rc=true
      ;;
    zsh)
      target_file="$HOME/.zshrc"
      is_shell_rc=true
      ;;
    bash)
      target_file="$HOME/.bashrc"
      is_shell_rc=true
      ;;
    alias|aliases)
      target_file="$HOME/.aliases"
      is_shell_rc=true
      ;;
    nvim|vim)
      target_file="$HOME/.config/nvim"
      ;;
    dotfiles|dots)
      target_file="$HOME/Codes/dotfiles"
      ;;
    git)
      target_file="$HOME/.gitconfig"
      ;;
    starship)
      target_file="$HOME/.config/starship.toml"
      ;;
    *)
      if [ -f "$1" ] || [ -d "$1" ]; then
        target_file="$1"
      else
        echo "Unknown config target: $1"
        echo "Usage: conf [shell|alias|nvim|dotfiles|git|starship|<path>]"
        return 1
      fi
      ;;
  esac

  local editor="${EDITOR:-nvim}"
  command -v "$editor" &>/dev/null || editor="nano"

  # If opening a directory, open directly
  if [ -d "$target_file" ]; then
    "$editor" "$target_file"
    return 0
  fi

  [ ! -f "$target_file" ] && touch "$target_file"

  local before_sum
  before_sum=$(cksum "$target_file" 2>/dev/null)

  "$editor" "$target_file"

  local after_sum
  after_sum=$(cksum "$target_file" 2>/dev/null)

  # Only reload if the file was modified and it's a shell rc file
  if [ "$before_sum" != "$after_sum" ]; then
    if [ "$is_shell_rc" = true ]; then
      echo "Changes detected. Sourcing $target_file..."
      source "$target_file"
      echo "✔ Terminal environment updated!"
    else
      echo "✔ Saved changes to $target_file"
    fi
  else
    echo "No changes made."
  fi
}
