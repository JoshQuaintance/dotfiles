# ==============================================================================
# String & Snippet Diff Helper (`zsh/functions/diff.zsh`)
# ==============================================================================
# Inline character/word diff and interactive `nvim -d` scratch diff (`strdiff`).

# String & Snippet Diff Helper (strdiff)
# Usage:
#   strdiff "str1" "str2"       -> Character-level inline diff in terminal
#   strdiff -w "str1" "str2"    -> Word-level inline diff in terminal
#   strdiff "str2"              -> Compare system clipboard against "str2"
#   strdiff [-i] ["s1" "s2"]    -> Open side-by-side scratch buffers in nvim -d
strdiff() {
  local mode="char"
  local interactive=false
  local args=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;137;180;250mstrdiff\033[0m — Compare strings, clipboard, or snippets\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  strdiff <str1> <str2>        Character-level inline diff in terminal\n"
        printf "  strdiff -w <str1> <str2>     Word-level inline diff in terminal\n"
        printf "  strdiff <str2>               Compare clipboard content against <str2>\n"
        printf "  strdiff [-i] [str1] [str2]   Interactive side-by-side diff in nvim -d\n\n"
        printf "\033[1mInteractive Controls (nvim -d):\033[0m\n"
        printf "  Paste/edit in either pane  Live diff updates automatically\n"
        printf "  Ctrl-w h / Ctrl-w l        Switch between left & right panes\n"
        printf "  ]c / [c                    Jump to next / previous diff hunk\n"
        printf "  q (in Normal mode)         Quit both panes & print diff summary\n"
        return 0
        ;;
      -i|--interactive)
        interactive=true
        shift
        ;;
      -w|--word)
        mode="word"
        shift
        ;;
      -c|--char)
        mode="char"
        shift
        ;;
      --)
        shift
        args+=("$@")
        break
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  # If no arguments provided, launch interactive side-by-side scratch mode
  if [ "${#args[@]}" -eq 0 ]; then
    interactive=true
  fi

  local str1=""
  local str2=""

  if [ "${#args[@]}" -eq 1 ]; then
    if ! str1="$(clippaste 2>/dev/null)"; then
      printf "\033[31m✖ Could not read from clipboard. Provide two strings: strdiff <str1> <str2>\033[0m\n" >&2
      return 1
    fi
    str2="${args[1]}"
  elif [ "${#args[@]}" -ge 2 ]; then
    str1="${args[1]}"
    str2="${args[2]}"
  fi

  # If an argument is an existing readable file path, read its contents
  [ -n "$str1" ] && [ -f "$str1" ] && [ -r "$str1" ] && str1="$(cat -- "$str1")"
  [ -n "$str2" ] && [ -f "$str2" ] && [ -r "$str2" ] && str2="$(cat -- "$str2")"

  if [ "$interactive" = true ]; then
    local tmp_left tmp_right
    tmp_left="$(mktemp -t "strdiff-left.XXXXXX")"
    tmp_right="$(mktemp -t "strdiff-right.XXXXXX")"
    [ -n "$str1" ] && printf "%s\n" "$str1" > "$tmp_left"
    [ -n "$str2" ] && printf "%s\n" "$str2" > "$tmp_right"

    if command -v nvim &>/dev/null; then
      nvim -d "$tmp_left" "$tmp_right" \
        -c "set diffopt+=linematch:60,algorithm:histogram" \
        -c "windo setlocal wrap number signcolumn=no | nnoremap <buffer> <silent> q :silent! wall! \| qa!<CR>" \
        -c "autocmd TextChanged,TextChangedI,InsertLeave * silent! diffupdate" \
        -c "autocmd VimLeavePre * silent! wall!" \
        -c "wincmd h"
    elif command -v vim &>/dev/null; then
      vim -d "$tmp_left" "$tmp_right"
    else
      "${EDITOR:-vi}" "$tmp_left" "$tmp_right"
    fi

    str1="$(cat -- "$tmp_left" 2>/dev/null)"
    str2="$(cat -- "$tmp_right" 2>/dev/null)"
    rm -f -- "$tmp_left" "$tmp_right"

    # If both scratch buffers are empty after closing, exit silently
    if [ -z "$str1" ] && [ -z "$str2" ]; then
      return 0
    fi
  fi

  "${DOTFILES_DIR:-$HOME/.dotfiles}/libexec/strdiff.py" "$str1" "$str2" "$mode"
}
