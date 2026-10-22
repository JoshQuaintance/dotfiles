# ==============================================================================
# Clipboard, Output Capture & Token Decoding (`zsh/functions/clipboard.zsh`)
# ==============================================================================
# Cross-platform clipboard I/O (`copy`, `clippaste`), clipboard transform pipeline
# (`clip`), last-command output capture (`lastout`), and JWT/epoch/Base64 decoder (`decode`).

# Cross-Platform Clipboard Helpers (macOS, Linux Wayland, Linux X11, WSL, SSH/OSC-52)
# WSL prefers win32yank.exe: clip.exe mangles UTF-8, and Get-Clipboard is slow and adds CRLF.
# Remote SSH / headless sessions fall back to OSC-52 escape sequences (with tmux passthrough).
# The paste side is `clippaste` so coreutils `paste` keeps working.
copy() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;137;180;250mcopy\033[0m — Cross-platform clipboard copy (macOS, Linux, WSL, SSH/OSC-52)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  echo <text> | copy   Copy text from stdin to system clipboard\n"
    printf "  copy <file>          Copy file contents to system clipboard\n"
    return 0
  fi
  if command -v pbcopy &>/dev/null; then
    pbcopy "$@"
  elif [[ -n "$WSL_DISTRO_NAME" ]] && command -v win32yank.exe &>/dev/null; then
    win32yank.exe -i --crlf
  elif [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy &>/dev/null; then
    wl-copy "$@"
  elif [[ -n "$DISPLAY" ]] && command -v xclip &>/dev/null; then
    xclip -selection clipboard "$@"
  elif [[ -n "$DISPLAY" ]] && command -v xsel &>/dev/null; then
    xsel --clipboard --input "$@"
  elif command -v clip.exe &>/dev/null; then
    # clip.exe reads the console code page unless given UTF-16LE with a BOM
    { printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE; } | clip.exe
  elif [[ -n "$TMUX" || -n "$SSH_TTY" || -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$DOTFILES_OSC52" ]]; then
    local data b64 target_tty="/dev/stdout"
    data="$(cat "$@"; printf x)"
    data="${data%x}"
    b64="$(printf "%s" "$data" | base64 | tr -d '\r\n')"
    if [[ -z "$DOTFILES_OSC52_STDOUT" ]]; then
      if [[ -n "$SSH_TTY" && -w "$SSH_TTY" ]]; then
        target_tty="$SSH_TTY"
      elif [[ -w /dev/tty ]]; then
        target_tty="/dev/tty"
      fi
    fi
    if [[ -n "$TMUX" ]]; then
      printf "%s" "$data" | tmux load-buffer - 2>/dev/null || true
      printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$b64" > "$target_tty"
    else
      printf "\033]52;c;%s\a" "$b64" > "$target_tty"
    fi
  else
    printf "\033[33mNo clipboard utility found (pbcopy, win32yank.exe, wl-copy, xclip, clip.exe, or SSH/OSC-52)\033[0m\n" >&2
    return 1
  fi
}

# Cross-Platform Clipboard Paste Helper (clippaste)
clippaste() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;137;180;250mclippaste\033[0m — Cross-platform clipboard paste helper\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  clippaste            Paste current clipboard content to stdout\n"
    return 0
  fi
  if command -v pbpaste &>/dev/null; then
    pbpaste "$@"
  elif [[ -n "$WSL_DISTRO_NAME" ]] && command -v win32yank.exe &>/dev/null; then
    win32yank.exe -o --lf
  elif [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-paste &>/dev/null; then
    wl-paste "$@"
  elif [[ -n "$DISPLAY" ]] && command -v xclip &>/dev/null; then
    xclip -selection clipboard -o "$@"
  elif [[ -n "$DISPLAY" ]] && command -v xsel &>/dev/null; then
    xsel --clipboard --output "$@"
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command '[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-Clipboard -Raw' | tr -d '\r'
  elif [[ -n "$TMUX" ]]; then
    tmux save-buffer -
  else
    printf "\033[33mNo clipboard utility found (pbpaste, win32yank.exe, wl-paste, xclip, powershell.exe)\033[0m\n" >&2
    return 1
  fi
}

# Universal Token, JWT, Epoch Timestamp, URL & Base64 Decoder (decode)
# Reads from argument, piped stdin, or system clipboard when called with no arguments
decode() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;203;166;247mdecode\033[0m — Auto-detecting JWT, Epoch timestamp, URL, and Base64 decoder\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  decode <value>       Decode JWT (eyJ...), epoch timestamp, URL, or Base64\n"
    printf "  echo <val> | decode  Decode from piped stdin\n"
    printf "  decode               Decode current clipboard content\n"
    return 0
  fi

  local input=""
  if (( $# > 0 )); then
    input="$*"
  elif [[ -p /dev/stdin || ( ! -t 0 && -s /dev/stdin ) ]]; then
    input="$(cat)"
  fi
  [[ -z "$input" ]] && input="$(clippaste 2>/dev/null)"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"

  if [[ -z "$input" ]]; then
    printf "\033[31m✖ Provide a value to decode, pipe via stdin, or copy to clipboard.\033[0m\n" >&2
    return 1
  fi

  "${DOTFILES_DIR:-$HOME/.dotfiles}/libexec/decode.py" "$input"
}

# Universal Multi-Format Text Encoder (encode)
# Encodes input into Base64, URL, Hex, HTML, and SHA-256 (or single format via flags)
encode() {
  local copy_to_clip=false
  local -a py_args=()

  while [[ "$1" == -* ]]; do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;203;166;247mencode\033[0m — Multi-format encoder (Base64, URL, Hex, HTML, SHA-256)\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  encode <text>             Print multi-format encoding card\n"
        printf "  encode -b, --b64 <text>   Print Base64 representation only\n"
        printf "  encode -u, --url <text>   Print URL-encoded representation only\n"
        printf "  encode -x, --hex <text>   Print Hex representation only\n"
        printf "  encode --html <text>      Print HTML-escaped representation only\n"
        printf "  encode -s, --sha256 <txt> Print SHA-256 hex digest only\n"
        printf "  encode -c, --copy <text>  Copy encoded result to system clipboard\n"
        printf "  echo <text> | encode      Encode from piped stdin\n"
        printf "  encode                    Encode current clipboard text\n"
        return 0
        ;;
      -c|--copy) copy_to_clip=true; shift ;;
      -b|--b64|-u|--url|-x|--hex|--html|-s|--sha256) py_args+=("$1"); shift ;;
      *) break ;;
    esac
  done

  local input=""
  if (( $# > 0 )); then
    input="$*"
  elif [[ -p /dev/stdin || ( ! -t 0 && -s /dev/stdin ) ]]; then
    input="$(cat)"
  fi
  [[ -z "$input" ]] && input="$(clippaste 2>/dev/null)"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"

  if [[ -z "$input" ]]; then
    printf "\033[31m✖ Provide text to encode, pipe via stdin, or copy to clipboard.\033[0m\n" >&2
    return 1
  fi

  local result
  result="$("${DOTFILES_DIR:-$HOME/.dotfiles}/libexec/encode.py" "${py_args[@]}" "$input")"
  if [[ "$copy_to_clip" == true ]]; then
    _copy_or_print "$result" "encoded text"
  else
    printf "%s\n" "$result"
  fi
}

# Quick Last-Command Output Capture (lastout)
# Re-executes the previous command (or an explicit command) and copies its output to clipboard,
# appends it to today's scratchpad, or opens it in a pager/Neovim.
# Usage:
#   lastout              -> Re-run last command & copy output to clipboard (or print if piped)
#   lastout -s           -> Re-run last command & append output block to today's scratchpad
#   lastout -p           -> Re-run last command & open output in $PAGER
#   lastout [-c|-s|-p] <cmd...> -> Run explicit command and capture output
lastout() {
  local mode="copy"
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;203;166;247mlastout\033[0m — Capture output of the last command to clipboard, scratchpad, or pager\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  lastout                  Re-run last command and copy output to clipboard\n"
        printf "  lastout -c, --copy       Copy output to system clipboard (default)\n"
        printf "  lastout -s, --scratch    Append command & output to today's scratchpad note\n"
        printf "  lastout -p, --pager      Open captured output in \${PAGER:-less -R}\n"
        printf "  lastout [flags] <cmd..>  Capture output of an explicit command\n"
        return 0
        ;;
      -c|--copy)
        mode="copy"
        shift
        ;;
      -s|--scratch)
        mode="scratch"
        shift
        ;;
      -p|--pager)
        mode="pager"
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf "\033[31m✖ Unknown option: %s\033[0m\n" "$1" >&2
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  local cmd_str=""
  if (( $# > 0 )); then
    cmd_str="$*"
  else
    local -a hist_lines
    hist_lines=("${(@f)$(fc -ln -5 -1 2>/dev/null)}")
    local idx
    for (( idx = ${#hist_lines[@]}; idx >= 1; idx-- )); do
      local candidate="${hist_lines[$idx]}"
      candidate="${candidate#"${candidate%%[![:space:]]*}"}"
      if [[ -n "$candidate" && "$candidate" != lastout* ]]; then
        cmd_str="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$cmd_str" ]]; then
    printf "\033[31m✖ No previous command found in history.\033[0m\n" >&2
    return 1
  fi

  local output rc=0
  if (( $# > 0 )); then
    output="$("$@" 2>&1)" || rc=$?
  else
    output="$(eval "$cmd_str" 2>&1)" || rc=$?
  fi

  case "$mode" in
    scratch)
      local scratch_dir="${SCRATCH_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/scratch}"
      mkdir -p "$scratch_dir"
      local note_file="$scratch_dir/$(date +%Y-%m-%d).md"
      {
        printf "\n## \`%s\` (%s)\n\n\`\`\`text\n%s\n\`\`\`\n" "$cmd_str" "$(date +%H:%M:%S)" "$output"
      } >> "$note_file"
      printf "\033[32m✔ Appended output of '%s' to %s\033[0m\n" "$cmd_str" "${note_file/$HOME/~}"
      ;;
    pager)
      if [[ -t 1 ]]; then
        printf "%s\n" "$output" | ${=PAGER:-less -R}
      else
        printf "%s\n" "$output"
      fi
      ;;
    copy)
      if [[ ! -t 1 ]]; then
        printf "%s\n" "$output"
      else
        _copy_or_print "$output" "output of '$cmd_str' (${#output} chars)"
      fi
      ;;
  esac
  return $rc
}

# Clipboard Transform Pipeline (clip)
# Transforms clipboard contents (or piped stdin) in-place or prints to stdout (-p).
# Supports: --trim, --json, --min, --sort, --lower, --upper, --urlencode, --urldecode, --b64e, --b64d
clip() {
  local op="" print_only=false
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;137;180;250mclip\033[0m — Cross-platform clipboard transform pipeline\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  clip                 Print current clipboard content\n"
        printf "  clip -t, --trim      Strip surrounding whitespace & trailing line spaces\n"
        printf "  clip -j, --json      Pretty-print JSON (2-space indent)\n"
        printf "  clip -m, --min       Minify JSON or collapse multi-line text to 1 line\n"
        printf "  clip -s, --sort      Sort lines and deduplicate\n"
        printf "  clip -l, --lower     Convert to lowercase\n"
        printf "  clip -u, --upper     Convert to uppercase\n"
        printf "  clip --urlencode     Percent-encode URL string\n"
        printf "  clip --urldecode     Decode percent-encoded URL string\n"
        printf "  clip --b64e          Encode as Base64\n"
        printf "  clip --b64d          Decode from Base64\n"
        printf "  clip -p, --print     Print transformed output to stdout instead of copying\n"
        return 0
        ;;
      -p|--print)     print_only=true; shift ;;
      -t|--trim)      op="trim"; shift ;;
      -j|--json)      op="json"; shift ;;
      -m|--min)       op="min"; shift ;;
      -s|--sort)      op="sort"; shift ;;
      -l|--lower)     op="lower"; shift ;;
      -u|--upper)     op="upper"; shift ;;
      --urlencode)    op="urlencode"; shift ;;
      --urldecode)    op="urldecode"; shift ;;
      --b64e)         op="b64e"; shift ;;
      --b64d)         op="b64d"; shift ;;
      *)
        printf "\033[31m✖ Unknown option: %s (see 'clip --help')\033[0m\n" "$1" >&2
        return 1
        ;;
    esac
  done

  local input=""
  if [[ -p /dev/stdin || ( ! -t 0 && -s /dev/stdin ) ]]; then
    input="$(cat)"
  fi
  if [[ -z "$input" ]]; then
    if ! input="$(clippaste 2>/dev/null)"; then
      printf "\033[31m✖ Failed to read from system clipboard.\033[0m\n" >&2
      return 1
    fi
  fi

  if [[ -z "$op" ]]; then
    printf "%s\n" "$input"
    return 0
  fi

  local transformed
  if ! transformed="$("${DOTFILES_DIR:-$HOME/.dotfiles}/libexec/clip_transform.py" "$op" "$input")"; then
    return 1
  fi

  if [[ "$print_only" == true ]]; then
    printf "%s\n" "$transformed"
  else
    printf "%s" "$transformed" | copy
    if [[ -t 1 ]]; then
      printf "\033[32m✔ Transformed clipboard (%s, %d chars)\033[0m\n" "$op" "${#transformed}"
    fi
  fi
}
