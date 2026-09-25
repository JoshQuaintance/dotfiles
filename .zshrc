# Ensure UTF-8 locale is always active and valid for Unicode & multibyte rendering
if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    _def_locale="en_US.UTF-8"
else
    _def_locale="C.UTF-8"
    if [ -d "/usr/lib/locale/en_US.utf8" ] || (command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qi "^en_US\.utf8$"); then
        _def_locale="en_US.UTF-8"
    fi
fi

# Override broken/unsupported locale if active on Linux
if [ "$_def_locale" = "C.UTF-8" ]; then
    if [ "$LANG" = "en_US.UTF-8" ] || [ "$LANG" = "en_US.utf8" ]; then
        export LANG="C.UTF-8"
    fi
    if [ "$LC_ALL" = "en_US.UTF-8" ] || [ "$LC_ALL" = "en_US.utf8" ]; then
        export LC_ALL="C.UTF-8"
    fi
fi

if [ -z "$LANG" ] || [ "$LANG" = "C" ] || [ "$LANG" = "POSIX" ]; then
    export LANG="$_def_locale"
fi
if [ -z "$LC_ALL" ] || [ "$LC_ALL" = "C" ] || [ "$LC_ALL" = "POSIX" ]; then
    export LC_ALL="$LANG"
fi
unset _def_locale


# Startup verbose checklist & environment banner
if [[ -o interactive ]] && [ -t 1 ] && [ "${ZSH_STARTUP_VERBOSE:-true}" = true ]; then
    _ZSH_STARTUP_VERBOSE=true
    zmodload zsh/datetime 2>/dev/null || true
    _t_start=$EPOCHREALTIME
    _t_step=$_t_start

    # Catppuccin Mocha palette
    _c_border="\033[38;2;203;166;247m"  # Mauve (#cba6f7)
    _c_check="\033[38;2;166;227;161m"   # Green (#a6e3a1)
    _c_title="\033[1;38;2;245;194;231m" # Pink (#f5c2e7)
    _c_key="\033[1;38;2;137;180;250m"   # Blue (#89b4fa)
    _c_dim="\033[38;2;108;112;134m"     # Overlay0 (#6c7086)
    _c_reset="\033[0m"

    _step() {
        if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
            local t_now=$EPOCHREALTIME
            local elapsed=$(( (t_now - _t_step) * 1000 ))
            _t_step=$t_now
            printf "${_c_border}▌${_c_reset}  ${_c_check}✔${_c_reset} %-44s ${_c_dim}%5.0fms${_c_reset}\n" "$1" "$elapsed"
        fi
    }

    if [[ "$OSTYPE" == darwin* ]]; then
        _os_logo=""
    else
        _os_logo="🐧"
    fi
    _raw_title="${ZSH_BANNER_TITLE:-${USER}@${HOST/.*/}}"
    _title="${_os_logo} ${_raw_title}"
else
    _ZSH_STARTUP_VERBOSE=false
    _step() { :; }
fi

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Homebrew environment (macOS Apple Silicon & Linuxbrew, fast static export)
if [ -d "/opt/homebrew" ]; then
    export HOMEBREW_PREFIX="/opt/homebrew"
    export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
    export HOMEBREW_REPOSITORY="/opt/homebrew"
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
    export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
    export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
    fpath=("/opt/homebrew/share/zsh/site-functions" $fpath)
    export C_INCLUDE_PATH="/opt/homebrew/include:$C_INCLUDE_PATH"
    export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"
elif [ -d "/home/linuxbrew/.linuxbrew" ]; then
    export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
    export HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
    export HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
    export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin${PATH+:$PATH}"
    export MANPATH="/home/linuxbrew/.linuxbrew/share/man${MANPATH+:$MANPATH}:"
    export INFOPATH="/home/linuxbrew/.linuxbrew/share/info:${INFOPATH:-}"
    fpath=("/home/linuxbrew/.linuxbrew/share/zsh/site-functions" $fpath)
elif [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
_step "Homebrew environment"

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="${DOTFILES_DIR:-$HOME/.dotfiles}/zsh/custom"
export ZSH_DISABLE_COMPFIX="true"
export SHORT_HOST="${HOST/.*/}"
export ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
ZSH_THEME="robbyrussell"
zstyle ':omz:update' mode disabled
plugins=(git)

# Precompile ~/.zcompdump to bytecode for instant loading
if [ -f "$ZSH_COMPDUMP" ] && [ ! -f "${ZSH_COMPDUMP}.zwc" -o "$ZSH_COMPDUMP" -nt "${ZSH_COMPDUMP}.zwc" ]; then
    zcompile "$ZSH_COMPDUMP" 2>/dev/null || true
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

# Disable Oh My Zsh's AUTO_CD (prevents jumping into folders named like commands e.g. 'gradle', 'dist', 'test')
unsetopt auto_cd
_step "Oh My Zsh & plugins (git)"

# Starship Prompt Initialization
if command -v starship &>/dev/null && [ "$TERM" != "dumb" ]; then
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

# Angular CLI autocompletion (cached to prevent spawning node on every launch)
if command -v ng &>/dev/null; then
    _ng_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ng_completion.zsh"
    if [ ! -s "$_ng_cache" ]; then
        mkdir -p "$(dirname "$_ng_cache")"
        ng completion script > "$_ng_cache" 2>/dev/null || rm -f "$_ng_cache"
    fi
    [ -s "$_ng_cache" ] && source "$_ng_cache"
fi
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

# FZF (Fuzzy finder integration & Catppuccin Mocha theme)
if command -v fzf &>/dev/null; then
    # Catppuccin Mocha color palette & ergonomics
    export FZF_DEFAULT_OPTS=" \
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
    --color=selected-bg:#45475a \
    --multi \
    --height=50% \
    --layout=reverse \
    --border=rounded \
    --prompt='❯ ' \
    --pointer='◆ ' \
    --marker='✓ '"

    # Fast file discovery via fd (includes hidden files, excludes .git)
    if command -v fd &>/dev/null; then
        export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"
    fi

    # Interactive previews for Ctrl-T (files) and Alt-C (directories)
    if command -v bat &>/dev/null; then
        export FZF_CTRL_T_OPTS="--preview 'if [ -d {} ]; then eza --tree --level=2 --color=always {} 2>/dev/null; else bat --style=numbers --color=always --line-range :300 {} 2>/dev/null; fi'"
    elif command -v eza &>/dev/null; then
        export FZF_CTRL_T_OPTS="--preview 'if [ -d {} ]; then eza --tree --level=2 --color=always {} 2>/dev/null; fi'"
    fi

    if command -v eza &>/dev/null; then
        export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {} 2>/dev/null'"
    fi

    source <(fzf --zsh 2>/dev/null) 2>/dev/null || true

    # FZF-Tab (interactive completion menu)
    for _fzf_tab in \
        "/opt/homebrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh" \
        "/usr/share/fzf-tab/fzf-tab.zsh" \
        "/home/linuxbrew/.linuxbrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/fzf-tab/fzf-tab.zsh"; do
        if [ -f "$_fzf_tab" ]; then
            source "$_fzf_tab"
            if command -v eza &>/dev/null; then
                zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null'
                zstyle ':fzf-tab:complete:z:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null'
            fi
            if command -v bat &>/dev/null; then
                zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [ -f "$realpath" ]; then bat --style=plain --color=always --line-range :50 "$realpath" 2>/dev/null; elif [ -d "$realpath" ]; then eza -1 --color=always "$realpath" 2>/dev/null; fi'
            fi
            zstyle ':fzf-tab:*' switch-group '<' '>'
            break
        fi
    done
fi

# Bat & Eza CLI themes (Catppuccin Mocha)
export BAT_THEME="Catppuccin Mocha"
export EZA_CONFIG_DIR="$HOME/.config/eza"
unset LS_COLORS

# Preferred editor for local and remote sessions
export EDITOR='nvim'
export VISUAL='nvim'

# GPG & Git signing terminal pinentry support (routes passphrase prompt to active terminal)
if [ -t 0 ] || [ -t 1 ]; then
    export GPG_TTY=$(tty 2>/dev/null || true)
fi
_step "CLI tools (Atuin, Zoxide, FZF, Bun, Bat)"

# ==========================================
# Functions & Aliases
# ==========================================
_dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"

[ -f "$_dot_dir/zsh/functions.zsh" ] && source "$_dot_dir/zsh/functions.zsh"
[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -f "$_dot_dir/.aliases" ] && [ ! -f "$HOME/.aliases" ] && source "$_dot_dir/.aliases"
_step "Dotfiles aliases & functions"

# Startup Summary Card & Rotating Tips
[ -f "$_dot_dir/zsh/banner.zsh" ] && source "$_dot_dir/zsh/banner.zsh"


# ==========================================
# Local / Machine-Specific Overrides
# ==========================================
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
[ -f "$HOME/.aliases.local" ] && source "$HOME/.aliases.local"
