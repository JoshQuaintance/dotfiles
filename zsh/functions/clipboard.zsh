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

  python3 - "$input" <<'PYEOF'
import base64
import datetime
import json
import re
import sys
import urllib.parse

raw = sys.argv[1].strip()
# Strip optional "Bearer " prefix
if raw.lower().startswith("bearer "):
    raw = raw[7:].strip()

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE  = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_RED   = "\033[1;38;2;243;139;168m"
C_DIM   = "\033[2m"
C_RST   = "\033[0m"


def b64url_decode(segment: str) -> bytes:
    padded = segment + "=" * ((4 - len(segment) % 4) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def fmt_epoch(ts: float) -> str:
    utc_dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
    local_dt = utc_dt.astimezone()
    now = datetime.datetime.now(tz=datetime.timezone.utc)
    delta = utc_dt - now
    secs = int(delta.total_seconds())
    abs_s = abs(secs)
    if abs_s >= 86400:
        rel = f"{abs_s // 86400}d {(abs_s % 86400) // 3600}h"
    elif abs_s >= 3600:
        rel = f"{abs_s // 3600}h {(abs_s % 3600) // 60}m"
    else:
        rel = f"{abs_s // 60}m {abs_s % 60}s"
    rel_str = f"in {rel}" if secs >= 0 else f"{rel} ago"
    return f"{utc_dt.strftime('%Y-%m-%d %H:%M:%S UTC')} | {local_dt.strftime('%Y-%m-%d %H:%M:%S %Z')} ({rel_str})"


# 1. JWT Detection (header.payload.signature)
parts = raw.split(".")
if len(parts) in (2, 3) and raw.startswith("eyJ"):
    try:
        hdr = json.loads(b64url_decode(parts[0]).decode("utf-8"))
        pay = json.loads(b64url_decode(parts[1]).decode("utf-8"))
        print(f"{C_MAUVE}🔑 JWT Header:{C_RST}")
        print(json.dumps(hdr, indent=2))
        print(f"\n{C_BLUE}📦 JWT Payload:{C_RST}")
        print(json.dumps(pay, indent=2))
        for claim in ("iat", "nbf", "exp"):
            if isinstance(pay.get(claim), (int, float)):
                val = float(pay[claim])
                status = ""
                if claim == "exp":
                    now_ts = datetime.datetime.now(tz=datetime.timezone.utc).timestamp()
                    status = f"{C_GREEN}✔ VALID{C_RST} " if val > now_ts else f"{C_RED}✖ EXPIRED{C_RST} "
                print(f"\n{C_BLUE}{claim}:{C_RST} {status}{fmt_epoch(val)}")
        sys.exit(0)
    except Exception:
        pass

# 2. Unix Epoch Timestamp (10-digit seconds or 13-digit milliseconds)
if re.fullmatch(r"\d{10}(\.\d+)?|\d{13}", raw):
    ts = float(raw)
    if len(raw.split(".")[0]) == 13:
        ts /= 1000.0
    print(f"{C_MAUVE}⏱  Epoch Timestamp:{C_RST} {raw}")
    print(f"{C_BLUE}➜{C_RST}  {fmt_epoch(ts)}")
    sys.exit(0)

# 3. URL / Percent-Encoded String
if "%" in raw or "://" in raw or ("?" in raw and "=" in raw):
    unquoted = urllib.parse.unquote_plus(raw)
    if unquoted != raw or "://" in raw:
        print(f"{C_MAUVE}🌐 Decoded URL:{C_RST}\n{unquoted}")
        parsed = urllib.parse.urlsplit(raw if "://" in raw else "http://x/?" + raw.lstrip("?"))
        qs = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
        if qs:
            print(f"\n{C_BLUE}Query Parameters:{C_RST}")
            for k, v in qs:
                print(f"  {C_GREEN}{k}{C_RST} = {v}")
        sys.exit(0)

# 4. Base64 (standard or URL-safe)
try:
    b_out = b64url_decode(raw).decode("utf-8")
    try:
        j_obj = json.loads(b_out)
        print(json.dumps(j_obj, indent=2))
    except Exception:
        print(b_out)
    sys.exit(0)
except Exception:
    print(f"{C_RED}✖ Could not decode input as JWT, Epoch timestamp, URL, or UTF-8 Base64.{C_RST}", file=sys.stderr)
    sys.exit(1)
PYEOF
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
  if ! transformed="$(python3 - "$op" "$input" <<'PYEOF'
import base64
import json
import sys
import urllib.parse

op, text = sys.argv[1], sys.argv[2]

if op == "trim":
    lines = [line.rstrip() for line in text.strip().splitlines()]
    print("\n".join(lines), end="")
elif op == "json":
    try:
        obj = json.loads(text)
        print(json.dumps(obj, indent=2, ensure_ascii=False), end="")
    except Exception as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
elif op == "min":
    try:
        obj = json.loads(text)
        print(json.dumps(obj, separators=(",", ":"), ensure_ascii=False), end="")
    except Exception:
        print(" ".join(text.split()), end="")
elif op == "sort":
    seen = set()
    lines = []
    for line in sorted(text.splitlines()):
        if line not in seen:
            seen.add(line)
            lines.append(line)
    print("\n".join(lines), end="")
elif op == "lower":
    print(text.lower(), end="")
elif op == "upper":
    print(text.upper(), end="")
elif op == "urlencode":
    print(urllib.parse.quote(text.strip(), safe=""), end="")
elif op == "urldecode":
    print(urllib.parse.unquote_plus(text.strip()), end="")
elif op == "b64e":
    print(base64.b64encode(text.encode("utf-8")).decode("ascii"), end="")
elif op == "b64d":
    raw = text.strip()
    padded = raw + "=" * ((4 - len(raw) % 4) % 4)
    print(base64.urlsafe_b64decode(padded.encode("ascii")).decode("utf-8", errors="replace"), end="")
PYEOF
  )"; then
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
