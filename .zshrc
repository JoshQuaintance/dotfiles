# Startup verbose checklist & environment banner
if [[ -o interactive ]] && [ -t 1 ] && [ "${ZSH_STARTUP_VERBOSE:-true}" = true ]; then
    _ZSH_STARTUP_VERBOSE=true
    # Ensure UTF-8 locale is active for proper multibyte character measurement in containers
    if [ "${#${:-🐧}}" -ne 1 ]; then
        for _loc in "C.UTF-8" "en_US.UTF-8" "C.utf8" "UTF-8"; do
            export LANG="$_loc" LC_ALL="$_loc" 2>/dev/null
            [ "${#${:-🐧}}" -eq 1 ] && break
        done
    fi
    zmodload zsh/datetime 2>/dev/null || true
    _t_start=$EPOCHREALTIME
    _t_step=$_t_start

    # Standard terminal ANSI colors (inherits directly from the active terminal palette)
    _c_border="\033[36m"
    _c_check="\033[32m"
    _c_title="\033[1;36m"
    _c_key="\033[1m"
    _c_reset="\033[0m"
    _c_dim="\033[2m"

    _step() {
        if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
            local t_now=$EPOCHREALTIME
            local elapsed=$(( (t_now - _t_step) * 1000 ))
            _t_step=$t_now
            printf "${_c_border}▌${_c_reset}  ${_c_check}✔${_c_reset} %-44s ${_c_dim}%5.0fms${_c_reset}\n" "$1" "$elapsed"
        fi
    }

    if [ "$(uname -s)" = "Darwin" ]; then
        _os_logo=""
    else
        _os_logo="🐧"
    fi
    _raw_title="${ZSH_BANNER_TITLE:-$(whoami)@$(hostname -s)}"
    _title="${_os_logo} ${_raw_title}"
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

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
zstyle ':omz:update' mode reminder
zstyle ':omz:plugins:eza' 'icons' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'hyperlink' yes
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

# GPG & Git signing terminal pinentry support (routes passphrase prompt to active terminal)
if [ -t 0 ] || [ -t 1 ]; then
    export GPG_TTY=$(tty 2>/dev/null || true)
fi
_step "CLI tools (Atuin, Zoxide, FZF, Bun)"

# ==========================================
# Functions & Aliases
# ==========================================
_dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
[ ! -d "$_dot_dir/.git" ] && [ -d "$HOME/Codes/dotfiles/.git" ] && _dot_dir="$HOME/Codes/dotfiles"

[ -f "$_dot_dir/zsh/functions.zsh" ] && source "$_dot_dir/zsh/functions.zsh"
[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -f "$_dot_dir/.aliases" ] && [ ! -f "$HOME/.aliases" ] && source "$_dot_dir/.aliases"
_step "Dotfiles aliases & functions"

# Startup Summary Card (Option 1: Left Accent Bar)
if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
    _t_total=$(( EPOCHREALTIME - _t_start ))
    _tot_str=$(printf "%.2fs" "$_t_total")
    _arch="$(uname -m)"
    _os_name="$(uname -s)"

    if [ "$_os_name" = "Darwin" ]; then
        _os_str="macOS (${_arch})"
    else
        _os_str="${_os_name} (${_arch})"
    fi

    # 1. Dotfiles info (fast shell reading without git subshell)
    _dot_branch=""
    _dot_hash=""
    if [ -f "$_dot_dir/.git/HEAD" ]; then
        read -r _head_line < "$_dot_dir/.git/HEAD"
        if [[ "$_head_line" == ref:\ * ]]; then
            _dot_branch="${_head_line#ref: refs/heads/}"
            _ref_file="$_dot_dir/.git/${_head_line#ref: }"
            if [ -f "$_ref_file" ]; then
                read -r _full_hash < "$_ref_file"
                _dot_hash="${_full_hash[1,7]}"
            fi
        else
            _dot_branch="detached"
            _dot_hash="${_head_line[1,7]}"
        fi
    fi
    [ -z "$_dot_branch" ] && _dot_branch="$(git -C "$_dot_dir" branch --show-current 2>/dev/null || echo "main")"
    [ -z "$_dot_hash" ] && _dot_hash="$(git -C "$_dot_dir" rev-parse --short HEAD 2>/dev/null || echo "")"
    _dot_info="${_dot_branch}${_dot_hash:+ (${_dot_hash})}"

    # 2. Battery status (macOS pmset + Linux sysfs /sys/class/power_supply)
    _batt_info=""
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
        fi
    elif [ -d /sys/class/power_supply ]; then
        # Linux laptops (safely omit via (N) nullglob if in container or desktop)
        local -a _bats
        _bats=(/sys/class/power_supply/BAT*(N) /sys/class/power_supply/battery(N))
        for _bat in "${_bats[@]}"; do
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
                break
            fi
        done
    fi

    if [ -z "$_batt_info" ]; then
        _batt_label="Network:"
        _batt_info="Online"
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
    _tip_line="💡 ${_random_tip}"

    # Render Left Accent Bar
    printf "${_c_border}▌${_c_reset}\n"
    printf "${_c_border}▌${_c_reset} ${_c_title}%s${_c_reset} ${_c_dim}•${_c_reset} %s ${_c_dim}•${_c_reset} %s ${_c_dim}•${_c_reset} ${_c_check}Ready in %s${_c_reset}\n" \
        "$_title" "$_os_str" "zsh ${ZSH_VERSION:-5.9}" "$_tot_str"
    printf "${_c_border}▌${_c_reset} ${_c_key}Dotfiles:${_c_reset} %s\n" "$_dot_info"
    printf "${_c_border}▌${_c_reset} ${_c_key}System:${_c_reset}   %s up ${_c_dim}•${_c_reset} %s RAM ${_c_dim}•${_c_reset} %s Disk ${_c_dim}•${_c_reset} %s %s\n" \
        "$_uptime_str" "$_mem_str" "$_disk_str" "$_batt_label" "$_batt_info"
    printf "${_c_border}▌${_c_reset} ${_c_dim}%s${_c_reset}\n" "$_tip_line"
    echo ""
fi


# ==========================================
# Local / Machine-Specific Overrides
# ==========================================
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
[ -f "$HOME/.aliases.local" ] && source "$HOME/.aliases.local"
