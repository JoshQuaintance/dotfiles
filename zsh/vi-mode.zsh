# Zsh Vi-Mode Configuration & Ergonomics

# 1. Enable Vi keybindings for ZLE (Zsh Line Editor)
bindkey -v

# 2. Instant Esc response (reduce key timeout from default 400ms to 10ms)
export KEYTIMEOUT=1

# 3. Allow editing command line in Neovim via 'v' in Normal Mode
autoload -Uz edit-command-line
zle -N edit-command-line

typeset -g _vi_mode_used_v=0

_vi_mode_edit_cmd() {
  _vi_mode_used_v=1
  edit-command-line "$@"
}
zle -N edit-command-line-wrapper _vi_mode_edit_cmd
bindkey -M vicmd 'v' edit-command-line-wrapper

# 4. Natural backspace and delete behavior across modes
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
bindkey -M vicmd '^?' backward-delete-char

# 5. Hybrid Insert Mode Conveniences (standard editing muscle memory)
bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^E' end-of-line
bindkey -M viins '^K' kill-line
bindkey -M viins '^U' backward-kill-line
bindkey -M viins '^W' backward-kill-word

# 6. Re-bind Atuin or FZF interactive history search in viins
if (( $+widgets[atuin-search-viins] )); then
  bindkey -M viins '^r' atuin-search-viins
  bindkey -M vicmd '/' atuin-search
elif (( $+widgets[fzf-history-widget] )); then
  bindkey -M viins '^r' fzf-history-widget
  bindkey -M vicmd '/' fzf-history-widget
fi

# 7. Dynamic cursor shape for modern terminals (beam in insert, block in normal)
function _vi_mode_cursor_shape() {
  case "$KEYMAP" in
    vicmd)      print -n '\e[2 q' ;; # Block cursor in normal mode
    viins|main) print -n '\e[5 q' ;; # Beam cursor in insert mode
  esac
  zle reset-prompt 2>/dev/null || true
}
zle -N zle-keymap-select _vi_mode_cursor_shape

function _vi_mode_line_init() {
  zle -K viins
  print -n '\e[5 q'
}
zle -N zle-line-init _vi_mode_line_init

function _vi_mode_line_finish() {
  print -n '\e[2 q'
}
zle -N zle-line-finish _vi_mode_line_finish

# 8. Script Execution Separation (between script input and output)
# When executing a multi-line script or a command edited via 'v' mode, renders a
# subtle horizontal divider between the script input lines and the start of its output.
autoload -Uz add-zsh-hook

_vi_mode_preexec_separator() {
  if (( _vi_mode_used_v )) || [[ "$1" == *$'\n'* ]]; then
    local cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    (( cols < 10 )) && cols=80
    # Catppuccin Mocha surface1 (#45475a) subtle horizontal rule
    printf "\033[38;2;69;71;90m%*s\033[0m\n" "$cols" '' | tr ' ' '─'
    _vi_mode_used_v=0
  fi
}

add-zsh-hook preexec _vi_mode_preexec_separator

