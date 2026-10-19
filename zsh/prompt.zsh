# ==============================================================================
# Dotfiles Unified Shell Prompt Manager
# Supports:
#   1. Fast Native (0-fork pure Zsh vcs_info — instant in PRoot / Termux / Android)
#   2. Spaceship (Feature-rich native Zsh async prompt with section streaming)
# ==============================================================================

_dotfiles_detect_prompt() {
    # 1. Environment variable override (explicit per-session override takes absolute precedence)
    if [[ -n "${DOTFILES_PROMPT:-}" ]]; then
        case "$DOTFILES_PROMPT" in
            native|spaceship)
                echo "$DOTFILES_PROMPT"
                return 0
                ;;
        esac
    fi

    # 2. Dynamic mobile terminal auto-detection (SSH_MOBILE, Blink, Termius, TERMUX_VERSION, Android)
    # Evaluated before persistent desktop ~/.config/dotfiles/prompt so remote mobile SSH connections
    # always auto-select native prompt to prevent fork latency, async worker stalls, and battery drain.
    local is_mobile=0
    if [[ "${_IS_MOBILE:-false}" == true || -n "${SSH_MOBILE:-}" ]]; then
        is_mobile=1
    elif [[ "${LC_TERMINAL:-}" == (Blink|Termius|blink|termius) || "${TERM_PROGRAM:-}" == (Blink|Termius|blink|termius) ]]; then
        is_mobile=1
    elif [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux" || -n "${PROOT_TMP_DIR:-}" ]]; then
        is_mobile=1
    elif [[ -f /proc/version ]] && grep -qiE '(android|samsung|qcom)' /proc/version 2>/dev/null; then
        is_mobile=1
    elif [[ "$(uname -r 2>/dev/null)" =~ (android|Android) ]]; then
        is_mobile=1
    fi

    if (( is_mobile )); then
        echo "native"
        return 0
    fi

    # 3. Explicit user preference file (~/.config/dotfiles/prompt) for desktop / standard sessions
    local pref_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/prompt"
    if [[ -f "$pref_file" ]]; then
        local chosen
        chosen="$(tr -d '[:space:]' < "$pref_file")"
        if [[ "$chosen" =~ ^(native|spaceship)$ ]]; then
            echo "$chosen"
            return 0
        fi
    fi

    # 4. Standard Desktop default: Spaceship if installed, else Native
    local _sp_candidate
    for _sp_candidate in \
        "/opt/homebrew/opt/spaceship/spaceship.zsh" \
        "/home/linuxbrew/.linuxbrew/opt/spaceship/spaceship.zsh" \
        "/usr/local/opt/spaceship/spaceship.zsh" \
        "$HOME/.spaceship-prompt/spaceship.zsh" \
        "$HOME/.oh-my-zsh/custom/themes/spaceship-prompt/spaceship.zsh"; do
        if [[ -f "$_sp_candidate" ]]; then
            echo "spaceship"
            return 0
        fi
    done

    echo "native"
}

_load_fast_native_prompt() {
    autoload -Uz vcs_info add-zsh-hook
    setopt PROMPT_SUBST

    zstyle ':vcs_info:*' enable git
    zstyle ':vcs_info:git:*' formats ' via %F{magenta} %b%f%F{red}%u%c%f'
    zstyle ':vcs_info:git:*' actionformats ' via %F{magenta} %b%f (%F{yellow}%a%f)%F{red}%u%c%f'
    # Keeping check-for-changes false guarantees 0 external git status forks
    zstyle ':vcs_info:git:*' check-for-changes false

    _fast_native_precmd() {
        vcs_info
    }
    add-zsh-hook precmd _fast_native_precmd

    typeset -g _native_prompt_char="%(?.%F{green}.%F{red})❯%f "
    PROMPT=$'\n%F{blue}%3~%f${vcs_info_msg_0_}%(?..%F{red} ✘ %?%f)\n${_native_prompt_char}'
    RPROMPT=""
}

_load_spaceship_prompt() {
    export SPACESHIP_CONFIG="${DOTFILES_DIR:-$HOME/.dotfiles}/config/spaceship/spaceship.zsh"
    # Suppress heavy async workers on mobile/SSH where zpty can hang or drain battery
    if [[ "${_IS_MOBILE:-false}" == true || -n "${SSH_MOBILE:-}" || "${LC_TERMINAL:-}" == (Blink|Termius|blink|termius) || "${TERM_PROGRAM:-}" == (Blink|Termius|blink|termius) ]]; then
        export SPACESHIP_PROMPT_ASYNC=false
    fi
    local _spaceship_entry=""
    local _sp_candidate
    for _sp_candidate in \
        "/opt/homebrew/opt/spaceship/spaceship.zsh" \
        "/home/linuxbrew/.linuxbrew/opt/spaceship/spaceship.zsh" \
        "/usr/local/opt/spaceship/spaceship.zsh" \
        "$HOME/.spaceship-prompt/spaceship.zsh" \
        "$HOME/.oh-my-zsh/custom/themes/spaceship-prompt/spaceship.zsh"; do
        if [[ -f "$_sp_candidate" ]]; then
            _spaceship_entry="$_sp_candidate"
            break
        fi
    done

    if [[ -n "$_spaceship_entry" ]]; then
        # Ensure extracted .zwc bytecode is newer than .zsh for 0ms startup
        if [[ ! "${_spaceship_entry}.zwc" -nt "$_spaceship_entry" ]]; then
            chmod -R u+w "${_spaceship_entry:h}" 2>/dev/null || true
            zcompile -R -- "${_spaceship_entry}.zwc" "$_spaceship_entry" 2>/dev/null || true
        fi
        # Clean up any running/orphaned Spaceship async workers before sourcing
        if (( $+functions[async_stop_worker] )); then
            async_stop_worker "spaceship" "spaceship_1" "spaceship_2" "spaceship_3" 2>/dev/null || true
        fi
        source "$_spaceship_entry"
        source "${DOTFILES_DIR:-$HOME/.dotfiles}/zsh/spaceship-patches.zsh"

        # Enforce synchronous prompt rendering in mobile / low-spec / SSH environments.
        # Must be enforced AFTER spaceship.zsh is sourced, because spaceship sources
        # $SPACESHIP_CONFIG which sets SPACESHIP_PROMPT_ASYNC=true for interactive ZLE.
        if [[ "${_IS_MOBILE:-false}" == true || -n "${SSH_MOBILE:-}" || "${LC_TERMINAL:-}" == (Blink|Termius|blink|termius) || "${TERM_PROGRAM:-}" == (Blink|Termius|blink|termius) ]]; then
            export SPACESHIP_PROMPT_ASYNC=false
            if (( $+functions[async_stop_worker] )); then
                async_stop_worker "spaceship" "spaceship_1" "spaceship_2" "spaceship_3" 2>/dev/null || true
            fi
        fi
    else
        _load_fast_native_prompt
    fi
}

# Main prompt initializer
_dotfiles_init_prompt() {
    [[ "$TERM" == "dumb" ]] && return 0

    local prompt_engine
    prompt_engine="$(_dotfiles_detect_prompt)"
    typeset -g DOTFILES_ACTIVE_PROMPT="$prompt_engine"

    case "$prompt_engine" in
        spaceship)
            _load_spaceship_prompt
            ;;
        native|*)
            _load_fast_native_prompt
            ;;
    esac
}

_dotfiles_init_prompt
