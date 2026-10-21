# ==============================================================================
# System Utilities, Diagnostics & Environment Helpers (`zsh/functions/system.zsh`)
# ==============================================================================
# Core system helpers (`y`, `open`, `dotenv`, `fsize`, `fknown`, `termtest`, `netinfo`, `checksum`).

# Yazi Shell Wrapper (changes directory on exit)
y() {
  local tmp
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  local cwd
  command yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp" 2>/dev/null)" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# Cross-platform `open` for Linux & WSL (macOS ships one; Debian's `open` is openvt)
#   open                 -> Open the current directory in the file manager
#   open <file|dir|url>  -> Open with the default app (WSL: Windows default app)
if [[ "$OSTYPE" != darwin* ]]; then
  DOTFILES_FUNCTIONS+=(open)
  open() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      printf "Usage: open [file|dir|url...]   Open with the default app (defaults to .)\n"
      return 0
    fi
    (( $# )) || set -- .
    local target
    for target in "$@"; do
      if [[ -n "$WSL_DISTRO_NAME" ]]; then
        if command -v wslview &>/dev/null; then
          wslview "$target"
        else
          # explorer.exe needs Windows paths and always exits 1
          [[ -e "$target" ]] && target="$(wslpath -w "$target")"
          explorer.exe "$target"
        fi
      elif command -v xdg-open &>/dev/null; then
        xdg-open "$target" &>/dev/null &!
      else
        printf "\033[33mNo opener found (xdg-open)\033[0m\n" >&2
        return 1
      fi
    done
    return 0
  }
fi

# Safe .env File Loader & Unloader (dotenv)
# Parses .env files in pure Zsh without eval (immune to command substitution injection)
# Usage:
#   dotenv [file...]     -> Load .env (or specified files) into current shell session
#   dotenv -u|--unload   -> Unset all variables loaded by dotenv in this session
#   dotenv -l|--list     -> List keys currently loaded by dotenv
typeset -gUa _DOTENV_LOADED_KEYS=()
dotenv() {
  # Delegate `dotenv run ...` to external dotenv CLI when present
  if [[ "$1" == "run" ]] && whence -p dotenv &>/dev/null; then
    command dotenv "$@"
    return $?
  fi
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;166;227;161mdotenv\033[0m — Safe .env environment loader & unloader (no eval)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  dotenv               Load ./.env into the current shell session\n"
    printf "  dotenv <file...>     Load one or more env files (e.g. dotenv .env .env.local)\n"
    printf "  dotenv -l, --list    List variables loaded by dotenv in this session\n"
    printf "  dotenv -u, --unload  Unset all variables loaded by dotenv in this session\n"
    return 0
  fi

  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    if (( ${#_DOTENV_LOADED_KEYS[@]} == 0 )); then
      printf "\033[33mNo variables currently loaded via dotenv.\033[0m\n"
      return 0
    fi
    local k
    for k in "${_DOTENV_LOADED_KEYS[@]}"; do
      if [[ -t 1 ]]; then
        printf "\033[1;38;2;137;180;250m%s\033[0m=%s\n" "$k" "${(P)k}"
      else
        printf "%s=%s\n" "$k" "${(P)k}"
      fi
    done
    return 0
  fi

  if [[ "$1" == "-u" || "$1" == "--unload" ]]; then
    local count="${#_DOTENV_LOADED_KEYS[@]}"
    if (( count == 0 )); then
      printf "\033[33mNo variables currently loaded via dotenv.\033[0m\n"
      return 0
    fi
    local k
    for k in "${_DOTENV_LOADED_KEYS[@]}"; do
      unset "$k"
    done
    _DOTENV_LOADED_KEYS=()
    printf "\033[32m✔ Unloaded %d variable(s) from shell session.\033[0m\n" "$count"
    return 0
  fi

  local -a files=("$@")
  (( ${#files[@]} == 0 )) && files=(".env")

  local f line key val
  local -a loaded_now=()
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      printf "\033[31m✖ Env file not found: %s\033[0m\n" "$f" >&2
      return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" == export[[:space:]]* ]]; then
        line="${line#export}"
        line="${line#"${line%%[![:space:]]*}"}"
      fi
      [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
      key="${line%%=*}"
      val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"

      if [[ "$val" == \"*\"* ]]; then
        # Double-quoted value: strip outer quotes (and any trailing comment after closing quote)
        val="${val#\"}"
        val="${val%\"*}"
        val="${val//\\n/$'\n'}"
        val="${val//\\t/$'\t'}"
        val="${val//\\\"/\"}"
        val="${val//\\\\/\\}"
      elif [[ "$val" == \'*\'* ]]; then
        # Single-quoted value: literal string inside quotes
        val="${val#\'}"
        val="${val%\'*}"
      else
        # Unquoted value: strip inline # comment and trailing whitespace
        [[ "$val" == *[[:space:]]\#* ]] && val="${val%%[[:space:]]\#*}"
        val="${val%"${val##*[![:space:]]}"}"
      fi

      typeset -gx "${key}=${val}"
      _DOTENV_LOADED_KEYS+=("$key")
      loaded_now+=("$key")
    done < "$f"
  done

  printf "\033[32m✔ Loaded %d variable(s) from %s\033[0m" "${#loaded_now[@]}" "${files[*]}"
  if (( ${#loaded_now[@]} > 0 )); then
    printf " \033[2m(%s)\033[0m" "${(j:, :)loaded_now}"
  fi
  printf "\n"
}

_dotenv() {
  _arguments \
    '(-l --list)'{-l,--list}'[List variables loaded by dotenv]' \
    '(-u --unload)'{-u,--unload}'[Unset variables loaded by dotenv]' \
    '(-h --help)'{-h,--help}'[Show usage help]' \
    '*:env file:_files -g "(.env*|.env.*|*.env)(-.)"'
}
(( $+functions[compdef] )) && compdef _dotenv dotenv || true

# Internal helper: list items in a directory sorted by disk usage (largest first)
_fsize_list() {
  local target_dir="${1:-.}"
  local -a items=("$target_dir"/*(DN))
  (( ${#items[@]} == 0 )) && return 0
  du -sh -- "${items[@]}" 2>/dev/null | sort -hr | awk -F'\t' 'NF>=2 {
    sz = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sz);
    p = $2;
    sub(/^\.\//, "", p);
    printf "%-10s\t%s\n", sz, p
  }'
}

# Interactive Directory Size & Large-File Hunter (fsize / bigfiles)
# Usage:
#   fsize [dir]        -> Browse files & directories sorted by disk size in modal-Vim FZF
#   fsize -l [dir]     -> Print size-sorted table (<size>\t<path>)
#   Keys: enter = cd/edit, x = move to Trash, y = copy path
fsize() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;249;226;175mfsize\033[0m (alias: \033[1mbigfiles\033[0m) — Interactive modal-Vim disk usage & large-file hunter\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fsize [dir]        Browse items in [dir] sorted largest-first\n"
    printf "  fsize -l [dir]     Print tab-separated size breakdown\n"
    printf "  Enter              cd into directory or open file in \$EDITOR\n"
    printf "  x                  Move selected item(s) to system Trash\n"
    printf "  y                  Copy path(s) to clipboard\n"
    return 0
  fi

  local list_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  fi

  local target_dir="${1:-.}"
  if [[ ! -d "$target_dir" ]]; then
    printf "\033[31m✖ Directory not found: %s\033[0m\n" "$target_dir" >&2
    return 1
  fi

  local rows
  rows="$(_fsize_list "$target_dir")"
  if [[ -z "$rows" ]]; then
    printf "\033[33mDirectory is empty: %s\033[0m\n" "$target_dir"
    return 0
  fi

  if [[ "$list_only" == true || ! -t 1 ]] || ! command -v fzf &>/dev/null; then
    printf "%s\n" "$rows"
    return 0
  fi

  local formatted
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' '{
    printf "\033[1;38;2;249;226;175m%-10s\033[0m\t\033[1;38;2;137;180;250m%s\033[0m\t%s\n", $1, $2, $2
  }')

  local hdr="  j/k: move │ space: select │ /: search │ enter: open/cd │ x: move to Trash │ y: copy path │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "📊 Disk Size (${target_dir}) > " "$hdr" "open" "space,x,y" "" "space:toggle+down"

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1,2 \
    --multi \
    --height=~55% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:yellow,pointer:bold:cyan,marker:bold:red" \
    --preview='p={3}; if [ -d "$p" ]; then if command -v eza &>/dev/null; then eza --tree --level=2 --icons --color=always "$p" 2>/dev/null; else ls -la "$p" 2>/dev/null; fi; elif [ -f "$p" ]; then if command -v bat &>/dev/null; then bat --color=always --style=numbers --line-range :100 "$p" 2>/dev/null; else head -n 100 "$p" 2>/dev/null; fi; fi' \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selection" || return 0

  local -a paths=()
  local c1 c2 p
  while IFS=$'\t' read -r c1 c2 p; do
    [[ -n "$p" ]] && paths+=("$p")
  done <<< "$selected_lines"
  (( ${#paths[@]} == 0 )) && return 0

  case "$key" in
    x)
      local item
      for item in "${paths[@]}"; do
        if command -v trash &>/dev/null; then
          trash "$item" && printf "  \033[32m✔\033[0m Moved to Trash: %s\n" "$item"
        elif command -v gio &>/dev/null; then
          gio trash "$item" && printf "  \033[32m✔\033[0m Moved to Trash: %s\n" "$item"
        else
          local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
          mkdir -p "$trash_dir"
          command mv -f -- "$item" "$trash_dir/" && printf "  \033[32m✔\033[0m Moved to %s: %s\n" "$trash_dir" "$item"
        fi
      done
      ;;
    y)
      _copy_or_print "${(j: :)paths}" "path(s): ${(j: :)paths}"
      ;;
    *)
      local first="${paths[1]}"
      if [[ -d "$first" ]]; then
        cd "$first"
      else
        _edit_file "$first"
      fi
      ;;
  esac
}

# Internal helper: list SSH known_hosts entries and active ControlMaster sockets
_fknown_list() {
  local kh_file="${1:-$HOME/.ssh/known_hosts}"
  local sock_dir="${2:-$HOME/.ssh/sockets}"

  if [[ -d "$sock_dir" ]]; then
    local s
    for s in "$sock_dir"/*(N); do
      [[ -S "$s" ]] && printf "socket\t%s\tActive SSH ControlMaster socket\n" "${s:t}"
    done
  fi

  if [[ -f "$kh_file" ]]; then
    awk '
      !/^[[:space:]]*(#|$)/ {
        host = $1;
        ktype = $2;
        sub(/,.*/, "", host);
        if (!seen[host]++) {
          printf "known_host\t%s\t%s (line %d)\n", host, ktype, NR
        }
      }
    ' "$kh_file" 2>/dev/null
  fi
}

# Interactive SSH Known-Hosts & Multiplexed Socket Manager (fknown)
# Usage:
#   fknown             -> Browse ~/.ssh/known_hosts & ~/.ssh/sockets in modal-Vim FZF
#   fknown <query>     -> Open pre-filtered by <query>
#   fknown -l, --list  -> Print tab-separated table
#   Keys: x = remove host key (ssh-keygen -R) or close socket, y = copy host
fknown() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;137;180;250mfknown\033[0m — Interactive SSH known_hosts & ControlMaster socket manager\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fknown             Browse known_hosts & active SSH sockets in FZF\n"
    printf "  fknown <query>     Open pre-filtered by <query>\n"
    printf "  fknown -l, --list  List known_hosts & active sockets\n"
    printf "  x                  Remove host key (ssh-keygen -R) or close socket\n"
    printf "  y                  Copy host / socket name to clipboard\n"
    return 0
  fi

  local list_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  fi

  local query="$*"
  local rows
  rows="$(_fknown_list)"
  if [[ -z "$rows" ]]; then
    printf "\033[33mNo SSH known_hosts entries or active sockets found.\033[0m\n"
    return 0
  fi

  if [[ "$list_only" == true || ! -t 1 ]] || ! command -v fzf &>/dev/null; then
    if [[ -n "$query" ]]; then
      printf "%s\n" "$rows" | grep -i "$query"
    else
      printf "%s\n" "$rows"
    fi
    return 0
  fi

  local formatted
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' '
    {
      kind = $1; target = $2; meta = $3;
      t_disp = target;
      if (length(t_disp) > 36) t_disp = substr(t_disp, 1, 33) "...";
      kinds[NR] = kind; tdisps[NR] = t_disp; metas[NR] = meta; targets[NR] = target;
      if (length(t_disp) > w_target) w_target = length(t_disp);
    }
    END {
      if (w_target < 24) w_target = 24;
      for (i = 1; i <= NR; i++) {
        kind = kinds[i];
        if (kind == "socket") k_col = sprintf("\033[38;2;166;227;161m⚡ %-8s\033[0m", "socket");
        else                  k_col = sprintf("\033[38;2;137;180;250m🔑 %-8s\033[0m", "host");
        printf "%s\t\033[1m%-*s\033[0m\t\033[2m%s\033[0m\t%s\t%s\n", k_col, w_target, tdisps[i], metas[i], kind, targets[i]
      }
    }
  ')

  local hdr="  j/k: move │ space: select │ /: search │ enter/y: copy host │ x: remove key / close socket │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "🔐 SSH Known Hosts & Sockets > " "$hdr" "copy" "space,x,y" "$query" "space:toggle+down"

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --multi \
    --height=~55% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:blue,pointer:bold:cyan,marker:bold:red" \
    --preview='kind={4}; target={5}; if [ "$kind" = "socket" ]; then ls -la "$HOME/.ssh/sockets/$target" 2>/dev/null; else ssh-keygen -l -F "$target" 2>/dev/null; fi' \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selection" || return 0

  local -a targets=()
  local c1 c2 c3 kind target
  while IFS=$'\t' read -r c1 c2 c3 kind target; do
    [[ -z "$target" ]] && continue
    targets+=("$target")
    if [[ "$key" == "x" ]]; then
      if [[ "$kind" == "socket" ]]; then
        command rm -f -- "$HOME/.ssh/sockets/$target"
        printf "  \033[32m✔\033[0m Closed SSH ControlMaster socket: %s\n" "$target"
      else
        ssh-keygen -R "$target" >/dev/null 2>&1
        printf "  \033[32m✔\033[0m Removed host key from known_hosts: %s\n" "$target"
      fi
    fi
  done <<< "$selected_lines"

  if [[ "$key" != "x" ]] && (( ${#targets[@]} > 0 )); then
    _copy_or_print "${(j: :)targets}" "SSH host(s): ${(j: :)targets}"
  fi
}

# Terminal Truecolor, Catppuccin Palette, Font Attributes & Nerd Font Diagnostic Card (termtest)
termtest() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;203;166;247mtermtest\033[0m — Render Truecolor, Catppuccin Mocha, font styles, and Nerd Font glyph diagnostics\n"
    return 0
  fi

  local cols="${COLUMNS:-80}"
  local lines="${LINES:-24}"
  printf "\n\033[1;38;2;203;166;247m╭────────────────────────────────────────────────────────╮\033[0m\n"
  printf "\033[1;38;2;203;166;247m│\033[0m  \033[1mTerminal Capabilities & Glyph Diagnostic (termtest)\033[0m   \033[1;38;2;203;166;247m│\033[0m\n"
  printf "\033[1;38;2;203;166;247m╰────────────────────────────────────────────────────────╯\033[0m\n\n"

  printf "  \033[1;38;2;137;180;250mTERM:\033[0m         %s\n" "${TERM:-unknown}"
  printf "  \033[1;38;2;137;180;250mCOLORTERM:\033[0m    %s\n" "${COLORTERM:-none}"
  printf "  \033[1;38;2;137;180;250mTERM_PROGRAM:\033[0m %s\n" "${TERM_PROGRAM:-${WT_SESSION:+Windows Terminal}}"
  printf "  \033[1;38;2;137;180;250mViewport:\033[0m     %sx%s cols/rows\n" "$cols" "$lines"
  printf "  \033[1;38;2;137;180;250mLocale:\033[0m       %s\n\n" "${LANG:-${LC_ALL:-POSIX}}"

  printf "  \033[1m1. 24-Bit Truecolor RGB Gradient:\033[0m\n  "
  local i r g b
  for (( i = 0; i < 48; i++ )); do
    r=$(( 255 - (i * 255 / 47) ))
    g=$(( i < 24 ? (i * 255 / 23) : ((47 - i) * 255 / 23) ))
    b=$(( i * 255 / 47 ))
    printf "\033[48;2;%d;%d;%dm " "$r" "$g" "$b"
  done
  printf "\033[0m\n\n"

  printf "  \033[1m2. Catppuccin Mocha Swatches:\033[0m\n  "
  local rgb
  for rgb in "245;224;220" "242;205;205" "245;194;231" "203;166;247" "243;139;168" "250;179;135" "249;226;175" "166;227;161" "148;226;213" "137;220;235" "116;199;236" "137;180;250" "180;190;254"; do
    printf "\033[48;2;%sm   \033[0m " "$rgb"
  done
  printf "\n\n"

  printf "  \033[1m3. Text Attributes:\033[0m\n"
  printf "  \033[1mBold\033[0m  │  \033[2mDim\033[0m  │  \033[3mItalic\033[0m  │  \033[4mUnderline\033[0m  │  \033[9mStrikethrough\033[0m  │  \033[7mReverse\033[0m\n\n"

  printf "  \033[1m4. Nerd Font & Unicode Glyphs:\033[0m\n"
  printf "  OS:  🐧 🪟  │  Git:     │  Status: ✔ ✖ ⚠ ⚡  │  UI: ❯ ◆ 🚀 📂 🐳 🔌\n\n"
}

# Cross-Platform Network, DNS, Tunnel & Latency Diagnostic Card (netinfo / ,net / fnet)
# Works across macOS, Linux, and WSL
netinfo() {
  local fetch_public=false run_ping=true
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;137;180;250mnetinfo\033[0m (aliases: \033[1m,net\033[0m, \033[1mfnet\033[0m) — Cross-platform network, DNS, VPN & latency diagnostic card\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  netinfo              Show active interface, LAN IP, gateway, DNS, VPN tunnels & ping\n"
        printf "  netinfo -p, --public Also query external public IP address\n"
        printf "  netinfo --no-ping    Skip 1.1.1.1 latency probe\n"
        return 0
        ;;
      -p|--public) fetch_public=true; shift ;;
      --no-ping)   run_ping=false; shift ;;
      *)           shift ;;
    esac
  done

  local iface="" lan_ip="" gateway="" dns_list="" tunnels="" ping_rtt="" pub_ip=""
  if [[ "$OSTYPE" == darwin* ]]; then
    iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
    [[ -z "$iface" ]] && iface="en0"
    lan_ip="$(ipconfig getifaddr "$iface" 2>/dev/null)"
    gateway="$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"
    dns_list="$(scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/{print $3}' | awk '!seen[$0]++' | paste -sd ', ' -)"
    tunnels="$(ifconfig 2>/dev/null | awk '
      /^(utun|ppp|wg|tun|tap|tailscale)[0-9]*:/ { iface=$1; sub(/:/, "", iface) }
      iface != "" && $1 == "inet" { printf "%s (%s) ", iface, $2; iface="" }
    ')"
  else
    local route_line
    route_line="$(ip -4 route get 1.1.1.1 2>/dev/null | head -n 1)"
    iface="$(printf "%s\n" "$route_line" | awk '{for(i=1;i<=NF;i++) if($i=="dev" && i<NF){print $(i+1); exit}}')"
    lan_ip="$(printf "%s\n" "$route_line" | awk '{for(i=1;i<=NF;i++) if($i=="src" && i<NF){print $(i+1); exit}}')"
    [[ -z "$lan_ip" ]] && lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    gateway="$(printf "%s\n" "$route_line" | awk '{for(i=1;i<=NF;i++) if($i=="via" && i<NF){print $(i+1); exit}}')"
    tunnels="$(ip -4 -o addr show 2>/dev/null | awk '$2 ~ /^(tun|tap|wg|tailscale|utun|ppp)/ { sub(/\/.*/, "", $4); printf "%s (%s) ", $2, $4 }')"
  fi

  if [[ -z "$dns_list" && -f /etc/resolv.conf ]]; then
    dns_list="$(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf 2>/dev/null | awk '!seen[$0]++' | paste -sd ', ' -)"
  fi

  if [[ "$run_ping" == true ]] && command -v ping &>/dev/null; then
    local ping_out
    if [[ "$OSTYPE" == darwin* ]]; then
      ping_out="$(ping -c 1 -t 1 1.1.1.1 2>/dev/null)"
    else
      ping_out="$(ping -c 1 -W 1 1.1.1.1 2>/dev/null)"
    fi
    ping_rtt="$(printf "%s\n" "$ping_out" | awk -F'time=' 'NF>1 {print $2; exit}')"
  fi

  if [[ "$fetch_public" == true ]] && command -v curl &>/dev/null; then
    pub_ip="$(curl -fsSL --max-time 2 https://icanhazip.com 2>/dev/null | tr -d '[:space:]')"
  fi

  printf "\n\033[1;38;2;137;180;250m╭────────────────────────────────────────────────────────╮\033[0m\n"
  printf "\033[1;38;2;137;180;250m│\033[0m  \033[1m🌐 Network & Connectivity Diagnostic (netinfo)\033[0m        \033[1;38;2;137;180;250m│\033[0m\n"
  printf "\033[1;38;2;137;180;250m╰────────────────────────────────────────────────────────╯\033[0m\n\n"
  printf "  \033[1;38;2;203;166;247mHostname:\033[0m     %s\n" "${HOST:-$(hostname 2>/dev/null)}"
  printf "  \033[1;38;2;203;166;247mInterface:\033[0m    %s\n" "${iface:-unknown}"
  printf "  \033[1;38;2;203;166;247mLocal IPv4:\033[0m   \033[1;38;2;166;227;161m%s\033[0m\n" "${lan_ip:-offline}"
  printf "  \033[1;38;2;203;166;247mGateway:\033[0m      %s\n" "${gateway:-none}"
  printf "  \033[1;38;2;203;166;247mDNS Servers:\033[0m  %s\n" "${dns_list:-none}"
  printf "  \033[1;38;2;203;166;247mVPN/Tunnels:\033[0m  %s\n" "${tunnels:-none active}"
  if [[ "$run_ping" == true ]]; then
    if [[ -n "$ping_rtt" ]]; then
      printf "  \033[1;38;2;203;166;247m1.1.1.1 RTT:\033[0m  \033[32m✔ %s\033[0m\n" "$ping_rtt"
    else
      printf "  \033[1;38;2;203;166;247m1.1.1.1 RTT:\033[0m  \033[33m⚠ unreachable / ICMP blocked\033[0m\n"
    fi
  fi
  if [[ "$fetch_public" == true ]]; then
    printf "  \033[1;38;2;203;166;247mPublic IP:\033[0m    %s\n" "${pub_ip:-unavailable}"
  fi
  printf "\n"
}

# File Checksum & Integrity Verifier (checksum / ,hash / hashfile / fhash)
# Computes MD5, SHA-1, SHA-256, and SHA-512 in a single pass and compares against an expected
# hash (or auto-detects a hex digest in the system clipboard).
# Usage:
#   checksum <file> [expected_hash]
#   checksum -c <file>           -> Copy SHA-256 hash to clipboard
checksum() {
  local copy_sha256=false
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;249;226;175mchecksum\033[0m (aliases: \033[1m,hash\033[0m, \033[1mhashfile\033[0m, \033[1mfhash\033[0m) — Multi-digest file checksum & integrity verifier\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  checksum <file>                 Compute MD5, SHA-1, SHA-256 & SHA-512 (auto-checks clipboard digest)\n"
        printf "  checksum <file> <expected_hex>  Verify file against expected checksum\n"
        printf "  checksum -c, --copy <file>      Also copy SHA-256 digest to clipboard\n"
        return 0
        ;;
      -c|--copy)
        copy_sha256=true
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  local file="$1"
  local expected="${2:-}"
  if [[ -z "$file" ]]; then
    printf "\033[33mUsage: checksum [-c] <file> [expected_hash]\033[0m\n" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    printf "\033[31m✖ File not found: %s\033[0m\n" "$file" >&2
    return 1
  fi

  local expected_source="argument"
  if [[ -z "$expected" ]]; then
    local clip_val
    clip_val="$(clippaste 2>/dev/null | tr -d '[:space:]')"
    if [[ "$clip_val" =~ ^[0-9a-fA-F]{32}$ || "$clip_val" =~ ^[0-9a-fA-F]{40}$ || "$clip_val" =~ ^[0-9a-fA-F]{64}$ || "$clip_val" =~ ^[0-9a-fA-F]{128}$ ]]; then
      expected="$clip_val"
      expected_source="clipboard"
    fi
  fi

  local out rc=0
  out="$("${DOTFILES_DIR:-$HOME/.dotfiles}/libexec/checksum.py" "$file" "$expected" "$expected_source")" || rc=$?

  local sha256_val=""
  local display_lines=()
  local line
  for line in "${(@f)out}"; do
    if [[ "$line" == __SHA256__:* ]]; then
      sha256_val="${line#__SHA256__:}"
    else
      display_lines+=("$line")
    fi
  done

  printf "%s\n" "${(F)display_lines}"
  if [[ "$copy_sha256" == true && -n "$sha256_val" ]]; then
    _copy_or_print "$sha256_val" "SHA-256: $sha256_val"
  fi
  return $rc
}
