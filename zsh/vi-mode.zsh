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

# 5b. Native Vim Text-Objects (ci", da', ci(, da{) & Surround (cs, ds, ys, visual S)
autoload -Uz select-quoted select-bracketed surround
zle -N select-quoted
zle -N select-bracketed
for _km in visual viopp; do
  for _c in {a,i}{\',\",\`}; do
    bindkey -M $_km $_c select-quoted
  done
  for _c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
    bindkey -M $_km $_c select-bracketed
  done
done
unset _km _c
zle -N delete-surround surround
zle -N add-surround surround
zle -N change-surround surround
bindkey -M vicmd 'cs' change-surround
bindkey -M vicmd 'ds' delete-surround
bindkey -M vicmd 'ys' add-surround
bindkey -M visual 'S' add-surround

# 5c. Sudo Prefix Toggle (double-Esc or Alt-s toggles 'sudo ' at start of command)
zmodload zsh/datetime 2>/dev/null || true
typeset -gF _vi_last_esc_time=0

_vi_toggle_sudo() {
  [[ -z "$BUFFER" ]] && LBUFFER="$(fc -ln -1)"
  if [[ "$BUFFER" == sudo\ * ]]; then
    BUFFER="${BUFFER#sudo }"
    (( CURSOR = CURSOR >= 5 ? CURSOR - 5 : 0 ))
  elif [[ -n "$BUFFER" ]]; then
    BUFFER="sudo $BUFFER"
    (( CURSOR += 5 ))
  fi
}
zle -N _vi_toggle_sudo
bindkey -M viins '^[s' _vi_toggle_sudo
bindkey -M vicmd '^[s' _vi_toggle_sudo

_vi_vicmd_esc() {
  if [[ -n "$EPOCHREALTIME" ]] && (( EPOCHREALTIME - _vi_last_esc_time < 0.35 )); then
    _vi_last_esc_time=0
    _vi_toggle_sudo
  else
    _vi_last_esc_time="${EPOCHREALTIME:-0}"
  fi
}
zle -N _vi_vicmd_esc
bindkey -M vicmd '\e' _vi_vicmd_esc

# 6. Re-bind Atuin or FZF interactive history search in viins
# bindkey -v above resets the viins keymap, wiping all bindings registered by
# atuin init zsh — restore them explicitly here.
if (( $+widgets[atuin-search-viins] )); then
  bindkey -M viins '^r'    atuin-search-viins
  bindkey -M viins '^[[A'  atuin-up-search-viins
  bindkey -M viins '^[OA'  atuin-up-search-viins
  bindkey -M vicmd '/'     atuin-search-vicmd
  bindkey -M vicmd '^[[A'  atuin-up-search-vicmd
  bindkey -M vicmd '^[OA'  atuin-up-search-vicmd
  bindkey -M vicmd 'k'     atuin-up-search-vicmd
elif (( $+widgets[fzf-history-widget] )); then
  bindkey -M viins '^r'   fzf-history-widget
  bindkey -M vicmd '/'    fzf-history-widget
fi

# 7. Dynamic cursor shape & Spaceship char symbol for modern terminals (beam in insert, block in normal)
function _vi_mode_sync_spaceship_char() {
  (( $+functions[spaceship::core::refresh_section] )) || return 0
  local sym="❯ "
  [[ "$KEYMAP" == "vicmd" ]] && sym="❮ "
  if [[ "$SPACESHIP_CHAR_SYMBOL_SUCCESS" != "$sym" ]]; then
    SPACESHIP_CHAR_SYMBOL="$sym"
    SPACESHIP_CHAR_SYMBOL_SUCCESS="$sym"
    SPACESHIP_CHAR_SYMBOL_FAILURE="$sym"
    spaceship::core::refresh_section --sync char
    spaceship::populate
  fi
}

function _vi_mode_cursor_shape() {
  case "$KEYMAP" in
    vicmd)
      _vi_last_esc_time="${EPOCHREALTIME:-0}"
      print -n '\e[2 q' # Block cursor in normal mode
      ;;
    viins|main)
      print -n '\e[5 q' # Beam cursor in insert mode
      ;;
  esac
  _vi_mode_sync_spaceship_char
  zle reset-prompt 2>/dev/null || true
}
zle -N zle-keymap-select _vi_mode_cursor_shape

function _vi_mode_line_init() {
  [[ "$KEYMAP" == "vicmd" ]] && zle -K viins
  print -n '\e[5 q'
  _vi_mode_sync_spaceship_char
  zle reset-prompt 2>/dev/null || true
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

