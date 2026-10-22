# ==============================================================================
# Zsh Vi-Mode Configuration & ZLE Ergonomics (zsh/vi-mode.zsh)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Core Vi Keymap & Instant Escape Response
# ------------------------------------------------------------------------------
bindkey -v
export KEYTIMEOUT=1               # Reduce Esc timeout from default 400ms to 10ms

# ------------------------------------------------------------------------------
# 2. Edit Command Line in Neovim ('v' in Normal Mode)
# ------------------------------------------------------------------------------
autoload -Uz edit-command-line
zle -N edit-command-line

typeset -g _vi_mode_used_v=0

_vi_mode_edit_cmd() {
  _vi_mode_used_v=1
  edit-command-line "$@"
}
zle -N edit-command-line-wrapper _vi_mode_edit_cmd
bindkey -M vicmd 'v' edit-command-line-wrapper

# ------------------------------------------------------------------------------
# 3. Natural Backspace & Hybrid Insert-Mode Conveniences
# ------------------------------------------------------------------------------
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
bindkey -M vicmd '^?' backward-delete-char

bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^E' end-of-line
bindkey -M viins '^K' kill-line
bindkey -M viins '^U' backward-kill-line
bindkey -M viins '^W' backward-kill-word

# ------------------------------------------------------------------------------
# 4. Native Vim Text-Objects (ci", da', ci(, da{) & Surround (cs, ds, ys, S)
# ------------------------------------------------------------------------------
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
zle -N add-surround    surround
zle -N change-surround surround

bindkey -M vicmd  'cs' change-surround
bindkey -M vicmd  'ds' delete-surround
bindkey -M vicmd  'ys' add-surround
bindkey -M visual 'S'  add-surround

# ------------------------------------------------------------------------------
# 5. Sudo Prefix Toggle (Double-Esc or Alt-s)
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 6. Inline Path & Glob Expansion (Alt-e or Ctrl-X p)
# ------------------------------------------------------------------------------
_vi_expand_path_under_cursor() {
  if [[ -z "${LBUFFER}${RBUFFER}" && -n "$BUFFER" ]]; then
    local idx="${CURSOR:-${#BUFFER}}"
    LBUFFER="${BUFFER[1,$idx]}"
    RBUFFER="${BUFFER[$(( idx + 1 )),-1]}"
  fi
  [[ -z "${LBUFFER}${RBUFFER}" ]] && return 0

  local lbuf="$LBUFFER" rbuf="$RBUFFER"
  local word_tail="${rbuf%%[[:space:]]*}"
  lbuf="${lbuf}${word_tail}"
  rbuf="${rbuf#${word_tail}}"

  local token="${lbuf##*[[:space:]]}"
  [[ -z "$token" ]] && return 0
  local prefix="${lbuf[1,$(( ${#lbuf} - ${#token} ))]}"

  local raw="${token#[\"\']}"
  raw="${raw%[\"\']}"

  local expanded="$raw"
  if [[ "$expanded" == "~" ]]; then
    expanded="$HOME"
  elif [[ "$expanded" == "~/"* ]]; then
    expanded="$HOME/${expanded#\~/}"
  fi
  if [[ "$expanded" == *\$* && "$expanded" != *[\`\(]* ]]; then
    expanded="${(e)expanded}"
  fi

  local result=""
  if [[ "$expanded" == *[\*\?\[]* ]]; then
    local -a matches=( $~expanded(N) )
    if (( ${#matches[@]} > 0 )); then
      result="${(j: :)${matches[@]:A}}"
    fi
  fi
  [[ -z "$result" ]] && result="${expanded:A}"

  LBUFFER="${prefix}${result}"
  RBUFFER="$rbuf"
  BUFFER="${LBUFFER}${RBUFFER}"
  CURSOR=${#LBUFFER}
}
zle -N _vi_expand_path_under_cursor
bindkey -M viins '^[e' _vi_expand_path_under_cursor
bindkey -M vicmd '^[e' _vi_expand_path_under_cursor
bindkey -M viins '^Xp' _vi_expand_path_under_cursor
bindkey -M vicmd '^Xp' _vi_expand_path_under_cursor

# ------------------------------------------------------------------------------
# 7. Yank Command Buffer to System Clipboard (Ctrl-Y in Insert, Y in Normal)
# ------------------------------------------------------------------------------
_vi_yank_buffer_to_clipboard() {
  local buf="${BUFFER:-${LBUFFER}${RBUFFER}}"
  [[ -z "$buf" ]] && return 0
  if (( $+functions[copy] )); then
    printf "%s" "$buf" | copy
    zle -M "✔ Copied command to clipboard (${#buf} chars)" 2>/dev/null || true
  fi
}
zle -N _vi_yank_buffer_to_clipboard
bindkey -M viins '^Y' _vi_yank_buffer_to_clipboard
bindkey -M vicmd 'Y'  _vi_yank_buffer_to_clipboard

# Inline `, <cmd>` / command help preview card underneath prompt (Ctrl-/, Alt-h, Ctrl-X h)
if (( $+widgets[_comma_inline_help] )); then
  bindkey -M viins '^_'  _comma_inline_help
  bindkey -M vicmd '^_'  _comma_inline_help
  bindkey -M viins '^[h' _comma_inline_help
  bindkey -M vicmd '^[h' _comma_inline_help
  bindkey -M viins '^Xh' _comma_inline_help
  bindkey -M vicmd '^Xh' _comma_inline_help
fi

# ------------------------------------------------------------------------------
# 8. Atuin / FZF Interactive History Search Bindings
# ------------------------------------------------------------------------------
# `bindkey -v` resets the viins keymap, wiping bindings registered by `atuin init zsh`.
if (( $+widgets[atuin-search-viins] )); then
  bindkey -M viins '^r'    atuin-search-viins
  bindkey -M viins '^[[A'  atuin-up-search-viins
  bindkey -M viins '^[OA'  atuin-up-search-viins
  bindkey -M vicmd '/'     atuin-search-vicmd
  bindkey -M vicmd '^[[A'  atuin-up-search-vicmd
  bindkey -M vicmd '^[OA'  atuin-up-search-vicmd
  bindkey -M vicmd 'k'     atuin-up-search-vicmd
elif (( $+widgets[fzf-history-widget] )); then
  bindkey -M viins '^r'    fzf-history-widget
  bindkey -M vicmd '/'     fzf-history-widget
fi

# ------------------------------------------------------------------------------
# 9. Dynamic Cursor Shape & Prompt Mode Indicator (Beam = Insert, Block = Normal)
# ------------------------------------------------------------------------------
function _vi_mode_sync_prompt_char() {
  local sym="❯ "
  [[ "$KEYMAP" == "vicmd" ]] && sym="❮ "

  # Spaceship prompt integration
  if (( $+functions[spaceship::core::refresh_section] )); then
    if [[ "$SPACESHIP_CHAR_SYMBOL_SUCCESS" != "$sym" ]]; then
      SPACESHIP_CHAR_SYMBOL="$sym"
      SPACESHIP_CHAR_SYMBOL_SUCCESS="$sym"
      SPACESHIP_CHAR_SYMBOL_FAILURE="$sym"
      spaceship::core::refresh_section --sync char
      spaceship::populate
    fi
  fi

  # Fast Native prompt integration
  if [[ -n "${_native_prompt_char:-}" ]]; then
    if [[ "$KEYMAP" == "vicmd" ]]; then
      _native_prompt_char="%F{yellow}❮%f "
    else
      _native_prompt_char="%(?.%F{green}.%F{red})❯%f "
    fi
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
  _vi_mode_sync_prompt_char
  zle reset-prompt 2>/dev/null || true
}
zle -N zle-keymap-select _vi_mode_cursor_shape

function _vi_mode_line_init() {
  [[ "$KEYMAP" == "vicmd" ]] && zle -K viins
  print -n '\e[5 q'
  _vi_mode_sync_prompt_char
  zle reset-prompt 2>/dev/null || true
}
zle -N zle-line-init _vi_mode_line_init

function _vi_mode_line_finish() {
  print -n '\e[2 q'
}
zle -N zle-line-finish _vi_mode_line_finish

# ------------------------------------------------------------------------------
# 10. Multi-Line Script Execution Visual Separator
# ------------------------------------------------------------------------------
autoload -Uz add-zsh-hook

_vi_mode_preexec_separator() {
  if (( _vi_mode_used_v )) || [[ "$1" == *$'\n'* ]]; then
    local cols="${COLUMNS:-80}"
    (( cols < 10 )) && cols=80
    # Catppuccin Mocha surface1 (#45475a) subtle horizontal rule (0-fork pure Zsh UTF-8 repeat)
    print -r -- $'\e[38;2;69;71;90m'"${(l:$cols::─:):-}"$'\e[0m'
    _vi_mode_used_v=0
  fi
}

add-zsh-hook preexec _vi_mode_preexec_separator
