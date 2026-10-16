# UTF-8 locale setup lives in .zshenv (always sourced first); re-source it only if ~/.zshenv wasn't linked
if [[ -z "$LANG" || "$LANG" == (C|POSIX) ]]; then
    source "${${(%):-%x}:A:h}/.zshenv"
fi

# Mobile / PRoot / Termux detection: default to fast compact startup
if [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux" || -n "${PROOT_TMP_DIR:-}" ]] || \
   [[ -f /proc/version && "$(grep -iE '(android|samsung|qcom)' /proc/version 2>/dev/null)" ]] || \
   [[ "$(uname -r 2>/dev/null)" =~ (android|Android) ]]; then
    _IS_MOBILE=true
    ZSH_STARTUP_VERBOSE="${ZSH_STARTUP_VERBOSE:-false}"
fi

# Startup verbose checklist & environment banner
if [[ -o interactive ]] && { [ -t 1 ] || [ "${ZSH_BENCH_STEPS:-false}" = true ]; } && [ "${ZSH_STARTUP_VERBOSE:-true}" = true ]; then
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
fi

# WSL: let gh, git & co. open links in the Windows browser
if [[ -n "$WSL_DISTRO_NAME" && -z "$BROWSER" ]] && (( $+commands[wslview] )); then
    export BROWSER="wslview"
fi

# Resolve canonical dotfiles repository directory (follows ~/.zshrc symlink in CI or custom checkouts)
export DOTFILES_DIR="${DOTFILES_DIR:-${${(%):-%x}:A:h:h}}"

# Native Zsh Completions, Options, History & Terminal Title
export SHORT_HOST="${HOST/.*/}"
export ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
[ -d "$DOTFILES_DIR/zsh/custom/completions" ] && fpath=("$DOTFILES_DIR/zsh/custom/completions" $fpath)

autoload -Uz compinit
setopt extendedglob
if [[ -n "$ZSH_COMPDUMP"(#qN.mh-24) ]]; then
    compinit -u -C -d "$ZSH_COMPDUMP"
else
    compinit -u -d "$ZSH_COMPDUMP"
    zcompile -R -- "${ZSH_COMPDUMP}.zwc" "$ZSH_COMPDUMP" 2>/dev/null || true
fi
if [ -f "$ZSH_COMPDUMP" ] && [ ! -f "${ZSH_COMPDUMP}.zwc" -o "$ZSH_COMPDUMP" -nt "${ZSH_COMPDUMP}.zwc" ]; then
    zcompile -R -- "${ZSH_COMPDUMP}.zwc" "$ZSH_COMPDUMP" 2>/dev/null || true
fi
unsetopt extendedglob

# Completion styling (case-insensitive, hyphen/underscore insensitive, menu selection, caching)
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]-_}={[:upper:][:lower:]_-}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# Directory stack & navigation options (no auto_cd so folders like 'test'/'dist' don't hijack commands)
unsetopt auto_cd
setopt auto_pushd pushd_ignore_dups pushdminus interactivecomments multios long_list_jobs

# History configuration (shared across sessions, deduplicated, Atuin-compatible)
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt extended_history hist_expire_dups_first hist_ignore_dups hist_ignore_space hist_verify share_history
setopt hist_reduce_blanks hist_find_no_dups

# Keep secret assignments (FOO_TOKEN=..., export API_KEY=..., password=...) out of $HISTFILE.
# Atuin applies the same rule via history_filter in config/atuin/config.toml.
_dot_history_filter() {
    emulate -L zsh -o extendedglob
    # 2 = keep in this session's history (for up-arrow fixes) but never write it to disk
    [[ $1 == (#i)*[[:alnum:]_]#(token|secret|passw(or|)d|api_#key)[[:alnum:]_]#=[^[:space:]]* ]] && return 2
    return 0
}
autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _dot_history_filter

# Terminal window / tab title updates (shows ~/dir when idle, ~/dir — cmd when running)
if [[ "$TERM" != "dumb" ]] && [[ -t 1 ]]; then
    _zsh_title_precmd() {
        print -Pn "\e]2;%~\a"
    }
    _zsh_title_preexec() {
        local cmd="${1[(wr)^(*=*|sudo|ssh|mosh|rake|-*)]:gs/%/%%}"
        print -Pn "\e]2;%~ — $cmd\a"
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _zsh_title_precmd
    add-zsh-hook preexec _zsh_title_preexec
fi
_step "Zsh completions & options"

# ==========================================
# User Configuration & Tools
# ==========================================

# Compiled Init Cache: Eliminates runtime subshell and binary exec forks on startup.
# Caches static init scripts in ~/.cache/dotfiles/init/<tool>.zsh and compiles to .zwc.
_dot_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/init"
_load_cached_init() {
    local bin="$1"
    local bin_cmd="$2"
    local cache="$_dot_cache_dir/${bin}.zsh"
    local bin_path
    bin_path="$(command -v "$bin" 2>/dev/null || true)"
    [ -z "$bin_path" ] && return 1

    if [ ! -s "$cache" ] || [ "$bin_path" -nt "$cache" ]; then
        mkdir -p "$_dot_cache_dir" 2>/dev/null || true
        eval "$bin_cmd" > "$cache" 2>/dev/null || rm -f "$cache"
        [ -s "$cache" ] && zcompile -R -- "${cache}.zwc" "$cache" 2>/dev/null || true
    fi
    [ -s "$cache" ] && source "$cache"
}

# Mise (Polyglot Runtime & Node 24 Manager — loaded before prompt so PATH is ready)
_load_cached_init "mise" "mise activate zsh"
_step "Mise polyglot runtime"

# Shell Prompt Initialization (Fast Native or Spaceship)
if [ "$TERM" != "dumb" ] && [ -f "${DOTFILES_DIR:-$HOME/.dotfiles}/zsh/prompt.zsh" ]; then
    source "${DOTFILES_DIR:-$HOME/.dotfiles}/zsh/prompt.zsh"
fi
_step "Shell prompt (${DOTFILES_ACTIVE_PROMPT:-active})"

# NVM (Lazy-loaded fallback when Mise is not installed — saves ~800-1200ms on startup)
export NVM_DIR="$HOME/.nvm"
if ! command -v mise &>/dev/null && [ -s "$NVM_DIR/nvm.sh" ]; then
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

# Bun (appended so a mise-pinned bun wins; ~/.bun/bin still provides `bun add -g` binaries)
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$PATH:$BUN_INSTALL/bin"
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
_load_cached_init "atuin" "atuin init zsh"

# Zoxide (Smart directory jumper: 'z <folder>')
_load_cached_init "zoxide" "zoxide init zsh"

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
    --marker='✓ ' \
    --bind='ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up'"

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

    # fzf >= 0.48 ships 'fzf --zsh' (cached); older distro builds (e.g. Debian/Ubuntu apt) only ship example scripts
    if ! _load_cached_init "fzf" "fzf --zsh"; then
        for _fzf_script in \
            /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh \
            /usr/share/fzf/{key-bindings,completion}.zsh; do
            [ -f "$_fzf_script" ] && source "$_fzf_script"
        done
        unset _fzf_script
    fi

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

# SSH agent: macOS (launchd) and desktop Linux (gnome-keyring, systemd) already provide one. On WSL and
# headless Linux, share one agent per user through a fixed socket instead of starting one per shell.
if [[ "$OSTYPE" != darwin* && ! -S "$SSH_AUTH_SOCK" ]] && (( $+commands[ssh-agent] )); then
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    ssh-add -l &>/dev/null
    if (( $? == 2 )); then  # 2 = nothing listening on the socket
        mkdir -p -m 700 "$HOME/.ssh"
        rm -f "$SSH_AUTH_SOCK"
        ssh-agent -a "$SSH_AUTH_SOCK" &>/dev/null
    fi
fi

# GPG & Git signing terminal pinentry support (routes passphrase prompt to active terminal)
if [ -t 0 ] || [ -t 1 ]; then
    export GPG_TTY=$TTY
fi
_step "CLI tools (Atuin, Zoxide, FZF, Bun, Bat)"

# ==========================================
# Functions & Aliases
# ==========================================
_dot_dir="$DOTFILES_DIR"

[ -f "$_dot_dir/zsh/functions.zsh" ] && source "$_dot_dir/zsh/functions.zsh"
if [ -f "$_dot_dir/zsh/.aliases" ]; then
    source "$_dot_dir/zsh/.aliases"
elif [ -f "$HOME/.aliases" ]; then
    source "$HOME/.aliases"
fi
_step "Dotfiles aliases & functions"

# Vi-Mode Command Line Editing (Vim keybindings, dynamic cursor shape, Neovim 'v' integration)
[ -f "$_dot_dir/zsh/vi-mode.zsh" ] && source "$_dot_dir/zsh/vi-mode.zsh"

# Zsh Autosuggestions & Syntax Highlighting (macOS Homebrew, Linuxbrew, apt/dnf/pacman, ~/.local/share)
for _zsh_autosug in \
    "/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/home/linuxbrew/.linuxbrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-autosuggestions/zsh-autosuggestions.zsh"; do
    if [ -f "$_zsh_autosug" ]; then
        if [ ! "${_zsh_autosug}.zwc" -nt "$_zsh_autosug" ]; then
            zcompile -R -- "${_zsh_autosug}.zwc" "$_zsh_autosug" 2>/dev/null || true
        fi
        ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#6c7086"
        ZSH_AUTOSUGGEST_STRATEGY=(history completion)
        ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
        source "$_zsh_autosug"
        break
    fi
done
unset _zsh_autosug

for _zsh_synhl in \
    "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"; do
    if [ -f "$_zsh_synhl" ]; then
        if [ ! "${_zsh_synhl}.zwc" -nt "$_zsh_synhl" ]; then
            zcompile -R -- "${_zsh_synhl}.zwc" "$_zsh_synhl" 2>/dev/null || true
        fi
        ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
        source "$_zsh_synhl"
        break
    fi
done
unset _zsh_synhl
_step "Vi-mode & Zsh plugins (autosuggest, syntax)"

# Clean up init cache helper
unfunction _load_cached_init 2>/dev/null || true
unset _dot_cache_dir

# Startup Summary Card & Rotating Tips
[ -t 1 ] && [ -f "$_dot_dir/zsh/banner.zsh" ] && source "$_dot_dir/zsh/banner.zsh"


# ==========================================
# Local / Machine-Specific Overrides
# ==========================================
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
[ -f "$HOME/.aliases.local" ] && source "$HOME/.aliases.local"
