# Internal helper: list listening TCP ports across macOS (lsof) and Linux (lsof or ss)
_port_list_listening() {
  if command -v lsof &>/dev/null; then
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1 {
      split($9, a, ":");
      p = a[length(a)];
      key = p ":" $2;
      if (!seen[key]++) {
        printf "%-8s\t%-8s\t%-18s\t%s\n", p, $2, $1, $9
      }
    }' | sort -n -k1,1
  elif command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | awk 'NR>1 {
      split($4, a, ":");
      p = a[length(a)];
      pid = "-"; proc = "-";
      if (match($0, /pid=[0-9]+/)) {
        pid = substr($0, RSTART+4, RLENGTH-4);
      }
      if (match($0, /\("[^"]+"/)) {
        proc = substr($0, RSTART+2, RLENGTH-3);
      }
      key = p ":" pid;
      if (!seen[key]++) {
        printf "%-8s\t%-8s\t%-18s\t%s\n", p, pid, proc, $4
      }
    }' | sort -n -k1,1
  fi
}

# Interactive TCP Port Inspector & Killer (port / fport)
# Usage:
#   port / fport     -> Interactive modal-Vim FZF browser of all listening TCP ports
#   port <number>    -> Inspect process listening on <number>
#   port -k <number> -> Kill process listening on <number>
#   Keys: enter = SIGTERM (-15), x = SIGKILL (-9), o = open localhost URL, y = copy port, u = copy URL
port() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mport\033[0m (alias: \033[1mfport\033[0m) — Inspect, open, or kill processes listening on TCP ports\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  port / fport       Interactive modal-Vim FZF browser of listening ports\n"
    printf "  port <port>        Show process bound to <port>\n"
    printf "  port -k <port>     Terminate process bound to <port>\n"
    printf "  Enter              Graceful terminate (SIGTERM -15)\n"
    printf "  x                  Force kill (SIGKILL -9)\n"
    printf "  o                  Open http://localhost:<port> in system browser\n"
    printf "  y / u              Copy port number (y) or localhost URL (u) to clipboard\n"
    return 0
  fi

  local kill_mode=false
  if [ "$1" = "-k" ] || [ "$1" = "--kill" ]; then
    kill_mode=true
    shift
  fi

  local initial_query=""
  # Direct numeric port argument provided (or kill mode)
  if [ "$kill_mode" = true ] || [[ "$1" =~ ^:?[0-9]+$ ]]; then
    local target_port="${1#:}"
    if [ "$kill_mode" = true ]; then
      local pids=()
      if command -v lsof &>/dev/null; then
        pids=($(lsof -t -i :"$target_port" 2>/dev/null))
      elif command -v fuser &>/dev/null; then
        pids=($(fuser "${target_port}/tcp" 2>/dev/null))
      elif command -v ss &>/dev/null; then
        pids=($(ss -tlnp "sport = :$target_port" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u))
      fi
      if [ "${#pids[@]}" -eq 0 ]; then
        if ! command -v lsof &>/dev/null && ! command -v fuser &>/dev/null && ! command -v ss &>/dev/null; then
          printf "\033[31m✖ Neither lsof, fuser, nor ss is installed.\033[0m\n" >&2
          return 1
        fi
        printf "\033[33mNo process found listening on port %s.\033[0m\n" "$target_port"
        return 1
      fi
      kill -15 "${pids[@]}" 2>/dev/null || kill -9 "${pids[@]}" 2>/dev/null
      printf "\033[32m✔ Terminated process(es) on port %s (PID: %s)\033[0m\n" "$target_port" "${pids[*]}"
      return 0
    fi

    if command -v lsof &>/dev/null; then
      lsof -i :"$target_port" -P -n
    elif command -v ss &>/dev/null; then
      ss -tlnp "sport = :$target_port"
    else
      printf "\033[31m✖ Neither lsof nor ss is installed.\033[0m\n" >&2
      return 1
    fi
    return $?
  elif [ $# -gt 0 ]; then
    initial_query="$*"
  fi

  # No direct port specified: non-TTY or missing fzf prints table
  local rows
  rows="$(_port_list_listening)"
  if [ -z "$rows" ]; then
    printf "\033[33mNo listening TCP ports found.\033[0m\n"
    return 0
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "\033[1;38;2;137;180;250m%-8s\t%-8s\t%-18s\t%s\033[0m\n" "PORT" "PID" "PROCESS" "ADDRESS"
    if [ -n "$initial_query" ]; then
      printf "%s\n" "$rows" | grep -i "$initial_query"
    else
      printf "%s\n" "$rows"
    fi
    return 0
  fi

  local hdr=$'  j/k: move │ space: select │ enter: SIGTERM │ x: SIGKILL │ o: open URL │ y: copy port │ u: copy URL │ q: quit\n  PORT    \tPID     \tPROCESS           \tADDRESS'
  local -a fzf_mode_flags
  _fzf_vim_mode "🔌 Listening Ports > " "$hdr" "SIGTERM" "space,x,o,y,u" "$initial_query" "space:toggle+down"

  local selected
  selected=$(printf "%s\n" "$rows" | fzf \
    --delimiter='\t' \
    --multi \
    --height=~55% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:red,marker:bold:red" \
    --preview='pid=$(echo {2} | tr -d " "); p=$(echo {1} | tr -d " "); printf "\033[1;36mhttp://localhost:%s\033[0m\n\n" "$p"; if [ -n "$pid" ] && [ "$pid" != "-" ]; then ps -p "$pid" -o pid,ppid,user,%cpu,%mem,etime,command 2>/dev/null; echo ""; if command -v lsof &>/dev/null; then lsof -p "$pid" -iTCP -P -n 2>/dev/null | head -n 20; elif command -v ss &>/dev/null; then ss -tulpn 2>/dev/null | grep "pid=$pid" | head -n 20; fi; fi' \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selected" || return 0

  local first_line="${selected_lines%%$'\n'*}"
  local first_port="${${first_line%%$'\t'*}// /}"

  case "$key" in
    o)
      if [ -n "$first_port" ]; then
        open "http://localhost:${first_port}"
      fi
      return 0
      ;;
    y)
      [ -n "$first_port" ] && _copy_or_print "$first_port" "port ${first_port} to clipboard"
      return 0
      ;;
    u)
      [ -n "$first_port" ] && _copy_or_print "http://localhost:${first_port}" "http://localhost:${first_port} to clipboard"
      return 0
      ;;
  esac

  local sig="-15"
  local sig_label="SIGTERM (-15)"
  if [ "$key" = "x" ]; then
    sig="-9"
    sig_label="SIGKILL (-9)"
  fi

  local p_clean="" pid_clean=""
  while IFS=$'\t' read -r p_col pid_col proc_col addr_col; do
    p_clean="${p_col// /}"
    pid_clean="${pid_col// /}"
    if [ -n "$pid_clean" ] && [ "$pid_clean" != "-" ]; then
      if kill "$sig" "$pid_clean" 2>/dev/null || kill -9 "$pid_clean" 2>/dev/null; then
        printf "  \033[32m✔\033[0m Sent \033[1m%s\033[0m to \033[1m%s\033[0m (PID %s) on port \033[1;36m%s\033[0m\n" "$sig_label" "${proc_col// /}" "$pid_clean" "$p_clean"
      else
        printf "  \033[31m✖\033[0m Failed to kill PID %s on port %s\n" "$pid_clean" "$p_clean" >&2
      fi
    fi
  done <<< "$selected_lines"
}

# Internal helper: list user processes sorted by CPU and memory for `fkill`
_fkill_list_procs() {
  local target_user="${1:-${USER:-$(id -un 2>/dev/null)}}"
  ps -u "$target_user" -o pid=,%cpu=,%mem=,args= 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ {
      pid = $1; cpu = $2; mem = $3;
      cmd = "";
      for (i = 4; i <= NF; i++) cmd = cmd (i == 4 ? "" : " ") $i;
      comm = $4;
      if (match(cmd, /^\/[^ ]*\.app\/Contents\/MacOS\/[^ ]+/)) {
        comm = substr(cmd, RSTART, RLENGTH);
      }
      sub(/^.*[\/]/, "", comm);
      sub(/:$/, "", comm);
      if (length(comm) > 20) comm = substr(comm, 1, 20);
      if (length(cmd) > 90) cmd = substr(cmd, 1, 87) "...";
      printf "%-8s\t%6s%%\t%6s%%\t%-20s\t%s\n", pid, cpu, mem, comm, cmd
    }
  ' | sort -rn -k2,2 -k3,3
}

# Interactive Process Browser & Killer (fkill / kp)
# Usage:
#   fkill            -> Interactive modal-Vim FZF browser of user processes sorted by CPU/MEM
#   fkill <query>    -> Pre-filtered process browser (e.g. fkill node, kp gradle)
#   Keys: space = multi-select, enter = SIGTERM (-15), x = SIGKILL (-9)
fkill() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;243;139;168mfkill\033[0m (alias: \033[1mkp\033[0m) — Interactive modal-Vim process browser & killer (macOS & Linux)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fkill              Browse user processes sorted by CPU & memory\n"
    printf "  fkill <query>      Open filtered by <query> (e.g. fkill node)\n"
    printf "  Enter              Graceful terminate (SIGTERM -15)\n"
    printf "  x                  Force kill (SIGKILL -9)\n"
    return 0
  fi

  local query="$*"
  local target_user="${USER:-$(id -un 2>/dev/null)}"

  local rows
  rows="$(_fkill_list_procs "$target_user")"
  if [ -z "$rows" ]; then
    printf "\033[33mNo running processes found for user %s.\033[0m\n" "$target_user"
    return 0
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "\033[1;38;2;243;139;168m%-8s\t%7s\t%7s\t%-20s\t%s\033[0m\n" "PID" "CPU" "MEM" "PROCESS" "COMMAND"
    printf "%s\n" "$rows" | head -n 30
    return 0
  fi

  local hdr=$'  j/k: move │ space: select │ enter: SIGTERM (-15) │ x: SIGKILL (-9) │ /: search │ q: quit\n  PID     \t   CPU\t   MEM\tPROCESS             \tCOMMAND'
  local -a fzf_mode_flags
  _fzf_vim_mode "⚡ Processes > " "$hdr" "SIGTERM" "space,x" "$query" "space:toggle+down"

  local selection
  selection=$(printf "%s\n" "$rows" | fzf \
    --delimiter='\t' \
    --multi \
    --height=~55% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:red,pointer:bold:red,marker:bold:yellow" \
    --preview='pid=$(echo {1} | tr -d " "); if [ -n "$pid" ]; then ps -p "$pid" -o pid,ppid,user,%cpu,%mem,etime,command 2>/dev/null; echo ""; if command -v lsof &>/dev/null; then lsof -p "$pid" -i -P -n 2>/dev/null | head -n 15; fi; fi' \
    --preview-window='right:50%:wrap')

  local key selected_lines
  _fzf_split_expect "$selection" || return 0

  local sig="-15"
  local sig_name="SIGTERM (-15)"
  if [ "$key" = "x" ]; then
    sig="-9"
    sig_name="SIGKILL (-9)"
  fi

  local pid_clean="" proc_clean=""
  while IFS=$'\t' read -r pid_col cpu_col mem_col proc_col cmd_col; do
    pid_clean="${pid_col// /}"
    proc_clean="${proc_col// /}"
    if [ -n "$pid_clean" ]; then
      if kill "$sig" "$pid_clean" 2>/dev/null; then
        printf "  \033[32m✔\033[0m Sent \033[1m%s\033[0m to \033[1;36m%s\033[0m (PID %s)\n" "$sig_name" "$proc_clean" "$pid_clean"
      else
        printf "  \033[31m✖\033[0m Failed to signal PID %s (%s)\n" "$pid_clean" "$proc_clean" >&2
      fi
    fi
  done <<< "$selected_lines"
}

# Interactive Container Inspector for Podman & Docker (fcon / dps)
# Usage:
#   fcon / dps       -> Browse running & stopped containers in modal-Vim FZF with live logs preview
#   Keys: enter/l = follow logs, s = exec shell, r = restart, x = stop
fcon() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mfcon\033[0m (alias: \033[1mdps\033[0m) — Interactive modal-Vim Podman & Docker container manager\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fcon / dps         Browse running & stopped containers with live log preview\n"
    printf "  Enter / l          Follow live container logs (logs -f)\n"
    printf "  s                  Open interactive shell inside container (bash/sh)\n"
    printf "  r                  Restart selected container(s)\n"
    printf "  x                  Stop selected container(s)\n"
    return 0
  fi

  local rt="${CONTAINER_RUNTIME:-}"
  if [ -z "$rt" ]; then
    if command -v podman &>/dev/null && podman ps &>/dev/null; then
      rt="podman"
    elif [ -x "/opt/podman/bin/podman" ] && /opt/podman/bin/podman ps &>/dev/null; then
      rt="/opt/podman/bin/podman"
    elif command -v docker &>/dev/null && docker ps &>/dev/null; then
      rt="docker"
    elif command -v podman &>/dev/null; then
      rt="podman"
    elif command -v docker &>/dev/null; then
      rt="docker"
    else
      printf "\033[31m✖ Neither podman nor docker is installed.\033[0m\n" >&2
      return 1
    fi
  fi

  local raw_containers
  raw_containers=$("$rt" ps -a --format '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null)
  if [ -z "$raw_containers" ]; then
    # :t = tail (basename) without forking a subshell
    printf "\033[33mNo containers found (%s).\033[0m\n" "${rt:t}"
    return 0
  fi

  local formatted
  formatted=$(printf "%s\n" "$raw_containers" | awk -F'\t' '{
    id = substr($1, 1, 12);
    name = $2; if (length(name) > 24) name = substr(name, 1, 21) "...";
    st = $3; if (length(st) > 22) st = substr(st, 1, 19) "...";
    img = $4; if (length(img) > 28) img = substr(img, 1, 25) "...";
    ports = $5;
    if (st ~ /^Up/) {
      st_col = sprintf("\033[32m%-22s\033[0m", st);
    } else {
      st_col = sprintf("\033[2m%-22s\033[0m", st);
    }
    printf "\033[36m%-12s\033[0m\t\033[1m%-24s\033[0m\t%s\t%-28s\t%s\n", id, name, st_col, img, ports
  }')

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "\033[1;38;2;137;180;250m%-12s\t%-24s\t%-22s\t%-28s\t%s\033[0m\n" "CONTAINER ID" "NAME" "STATUS" "IMAGE" "PORTS"
    printf "%s\n" "$formatted"
    return 0
  fi

  local query="$*"
  local hdr=$'  j/k: move │ space: select │ enter/l: logs -f │ s: shell │ r: restart │ x: stop │ /: search │ q: quit\n  ID          \tNAME                    \tSTATUS                \tIMAGE                       \tPORTS'
  local -a fzf_mode_flags
  _fzf_vim_mode "🐳 Containers (${rt:t}) > " "$hdr" "follow logs" "space,l,s,r,x" "$query" "space:toggle+down"

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter='\t' \
    --multi \
    --height=~60% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:blue,marker:bold:yellow" \
    --preview="cid=\$(echo {1} | sed 's/\x1b\[[0-9;]*m//g' | tr -d ' '); [ -n \"\$cid\" ] && '$rt' logs --tail 60 \"\$cid\" 2>&1" \
    --preview-window='right:55%:wrap')

  local key selected_lines
  _fzf_split_expect "$selection" || return 0

  local -a cids cnames
  local cid="" cname=""
  while IFS=$'\t' read -r id_col name_col rest; do
    cid=$(printf "%s" "$id_col" | sed $'s/\x1b\\[[0-9;]*m//g' | tr -d ' ')
    cname=$(printf "%s" "$name_col" | sed $'s/\x1b\\[[0-9;]*m//g' | tr -d ' ')
    if [ -n "$cid" ]; then
      cids+=("$cid")
      cnames+=("${cname:-$cid}")
    fi
  done <<< "$selected_lines"

  [ ${#cids[@]} -eq 0 ] && return 0

  case "$key" in
    s)
      printf "\033[1;36m➜ Opening shell in %s...\033[0m\n" "${cnames[1]}"
      "$rt" exec -it "${cids[1]}" /bin/sh -c 'if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi'
      ;;
    r)
      "$rt" restart "${cids[@]}"
      printf "\033[32m✔ Restarted container(s): %s\033[0m\n" "${(j:, :)cnames}"
      ;;
    x)
      "$rt" stop "${cids[@]}"
      printf "\033[33m■ Stopped container(s): %s\033[0m\n" "${(j:, :)cnames}"
      ;;
    *)
      printf "\033[1;36m➜ Following logs for %s (Ctrl-C to exit)...\033[0m\n" "${cnames[1]}"
      "$rt" logs -f --tail 100 "${cids[1]}"
      ;;
  esac
}

# Interactive SSH Host Browser (fssh)
# Usage:
#   fssh             -> Browse SSH hosts from ~/.ssh/config in modal-Vim FZF
#   fssh <query>     -> Open pre-filtered by <query>
#   Keys: enter = ssh <host>, y = copy user@hostname, e = edit ~/.ssh/config at Host block
fssh() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mfssh\033[0m — Interactive modal-Vim SSH host picker (~/.ssh/config)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fssh               Browse configured SSH hosts with live config preview\n"
    printf "  fssh <query>       Open pre-filtered by <query>\n"
    printf "  Enter              Connect via 'ssh <host>'\n"
    printf "  y                  Copy [user@]hostname to clipboard\n"
    printf "  e                  Edit ~/.ssh/config at the selected Host entry\n"
    return 0
  fi

  local ssh_cfg="$HOME/.ssh/config"
  if [ ! -f "$ssh_cfg" ]; then
    printf "\033[33mNo ~/.ssh/config file found.\033[0m\n" >&2
    return 1
  fi

  local rows
  rows=$(awk '
    function flush_host() {
      if (host != "" && host !~ /\*/) {
        printf "\033[1;36m%-24s\033[0m\t%-30s\t%-16s\t%s\n", host, (hostname != "" ? hostname : "-"), (user != "" ? user : "-"), (port != "" ? port : "22")
      }
    }
    tolower($1) == "host" {
      flush_host()
      host = $2; hostname = ""; user = ""; port = ""
      next
    }
    tolower($1) == "hostname" { hostname = $2 }
    tolower($1) == "user"     { user = $2 }
    tolower($1) == "port"     { port = $2 }
    END { flush_host() }
  ' "$ssh_cfg" 2>/dev/null)

  if [ -z "$rows" ]; then
    printf "\033[33mNo named Host entries found in %s.\033[0m\n" "$ssh_cfg"
    return 0
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "\033[1;38;2;137;180;250m%-24s\t%-30s\t%-16s\t%s\033[0m\n" "HOST" "HOSTNAME" "USER" "PORT"
    printf "%s\n" "$rows"
    return 0
  fi

  local query="$*"
  local hdr=$'  j/k: move │ /: search │ enter: ssh connect │ y: copy target │ e: edit config │ q: quit\n  HOST                    \tHOSTNAME                      \tUSER            \tPORT'
  local -a fzf_mode_flags
  _fzf_vim_mode "🔐 SSH Hosts > " "$hdr" "connect" "y,e" "$query"

  local preview_cmd="
    h=\$(echo {1} | sed 's/\x1b\[[0-9;]*m//g' | tr -d ' ')
    awk -v target=\"\$h\" '
      tolower(\$1) == \"host\" {
        in_block = (\$2 == target)
      }
      in_block { print }
    ' '$ssh_cfg' | if command -v bat &>/dev/null; then bat --color=always --style=plain -l ssh_config 2>/dev/null || bat --color=always --style=plain; else cat; fi
  "

  local selection
  selection=$(printf "%s\n" "$rows" | fzf \
    --ansi \
    --delimiter='\t' \
    --height=~50% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    --preview="$preview_cmd" \
    --preview-window='right:50%:wrap')

  local key selected_lines selected_line
  _fzf_split_expect "$selection" || return 0
  selected_line="${selected_lines%%$'\n'*}"
  [ -z "$selected_line" ] && return 0

  local host_alias host_name user_name
  host_alias=$(printf "%s" "$selected_line" | awk -F'\t' '{print $1}' | sed $'s/\x1b\\[[0-9;]*m//g' | tr -d ' ')
  host_name=$(printf "%s" "$selected_line" | awk -F'\t' '{print $2}' | tr -d ' ')
  user_name=$(printf "%s" "$selected_line" | awk -F'\t' '{print $3}' | tr -d ' ')

  case "$key" in
    y)
      local target_str="$host_alias"
      if [ -n "$host_name" ] && [ "$host_name" != "-" ]; then
        if [ -n "$user_name" ] && [ "$user_name" != "-" ]; then
          target_str="${user_name}@${host_name}"
        else
          target_str="$host_name"
        fi
      fi
      _copy_or_print "$target_str" "SSH target to clipboard: $target_str"
      ;;
    e)
      local ln
      ln=$(grep -nE "^[[:space:]]*[Hh]ost[[:space:]]+${host_alias}([[:space:]]|$)" "$ssh_cfg" 2>/dev/null | head -n1 | cut -d: -f1)
      _edit_file "$ssh_cfg" "$ln"
      ;;
    *)
      printf "\033[1;32m➜\033[0m \033[1;36mssh %s\033[0m\n" "$host_alias"
      ssh "$host_alias"
      ;;
  esac
}

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

# Universal Archive Extractor (extract / x)
# Uses Rust-based `ouch` when available, with portable fallback to tar/unzip/7z/zstd.
extract() {
  if [ -z "$1" ]; then
    printf "\033[33mUsage: extract <archive_file>\033[0m\n" >&2
    printf "Supports: .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .zip, .rar, .7z, .tar.zst, .zst, .gz, .bz2\n" >&2
    return 1
  fi

  if [ ! -f "$1" ]; then
    printf "\033[31m✖ File not found: %s\033[0m\n" "$1" >&2
    return 1
  fi

  local file="$1"
  # :l = lowercase parameter expansion in Zsh
  case "${file:l}" in
    *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tar|*.bz2|*.rar|*.gz|*.zip|*.z|*.7z|*.zst)
      # Fast path: use `ouch decompress --here` when installed, falling back on error
      if command -v ouch &>/dev/null && ouch decompress --here -y "$file" 2>/dev/null; then
        return 0
      fi
      ;;
  esac

  case "${file:l}" in
    *.tar.bz2|*.tbz2)   tar xvjf "$file" ;;
    *.tar.gz|*.tgz)     tar xvzf "$file" ;;
    *.tar.xz|*.txz)     tar xvJf "$file" ;;
    *.tar.zst)          tar --zstd -xvf "$file" 2>/dev/null || zstd -d -c "$file" | tar xvf - ;;
    *.tar)              tar xvf "$file" ;;
    *.bz2)              bunzip2 "$file" ;;
    *.rar)              unrar x "$file" ;;
    *.gz)               gunzip "$file" ;;
    *.zip)              unzip "$file" ;;
    *.z)                uncompress "$file" ;;
    *.7z)               if command -v 7zz &>/dev/null; then 7zz x "$file"; else 7z x "$file"; fi ;;
    *.zst)              zstd -d "$file" ;;
    *)
      printf "\033[31m✖ Cannot extract '%s' — unsupported extension.\033[0m\n" "$file" >&2
      return 1
      ;;
  esac
}

# Tab completion for extract / x: complete supported archive files
_extract() {
  _files -g '*.(tar.bz2|tbz2|tar.gz|tgz|tar.xz|txz|tar.zst|tar|bz2|rar|gz|zip|Z|z|7z|zst)(-.)'
}
(( $+functions[compdef] )) && compdef _extract extract x || true

# Universal Archive Creator (pack)
# Companion to extract: creates archives from files/directories based on output extension.
# Uses Rust-based `ouch` when available, with portable fallback to tar/zip/7z/zstd.
# Usage:
#   pack <archive_name> <files/dirs...>   -> Create archive in specified format (.tar.gz, .zip, .tar.zst, .7z, etc.)
#   pack <directory>                      -> Defaults to <directory>.tar.gz
pack() {
  if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mpack\033[0m — Universal archive creator (companion to \033[1mextract\033[0m / \033[1mx\033[0m)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  pack <archive.ext> <files/dirs...>   Create archive inferred from extension\n"
    printf "  pack <folder>                        Create <folder>.tar.gz from <folder>\n\n"
    printf "\033[1mSupported formats:\033[0m\n"
    printf "  .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .tar.zst, .tar, .zip, .7z, .gz, .bz2, .zst\n"
    [ $# -eq 0 ] && return 1 || return 0
  fi

  local archive="$1"
  shift

  # Shorthand: 'pack <dir>' with 1 arg and no archive extension creates '<dir>.tar.gz'
  if [ $# -eq 0 ]; then
    local clean_target="${archive%/}"
    if [ -e "$clean_target" ]; then
      set -- "$clean_target"
      archive="${clean_target}.tar.gz"
    else
      printf "\033[33mUsage: pack <archive_file> <files_or_dirs...>\033[0m\n" >&2
      return 1
    fi
  fi

  local item
  for item in "$@"; do
    if [ ! -e "$item" ]; then
      printf "\033[31m✖ Target not found: %s\033[0m\n" "$item" >&2
      return 1
    fi
  done

  local rc=1
  # :l = lowercase parameter expansion in Zsh
  case "${archive:l}" in
    *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tar|*.zip|*.7z|*.gz|*.bz2|*.zst)
      if command -v ouch &>/dev/null && ouch compress -y "$@" "$archive" 2>/dev/null; then
        rc=0
      fi
      ;;
  esac

  if [ $rc -ne 0 ]; then
    case "${archive:l}" in
      *.tar.bz2|*.tbz2)   tar cjvf "$archive" "$@" ;;
      *.tar.gz|*.tgz)     tar czvf "$archive" "$@" ;;
      *.tar.xz|*.txz)     tar cJvf "$archive" "$@" ;;
      *.tar.zst)          tar --zstd -cvf "$archive" "$@" 2>/dev/null || { tar cvf - "$@" | zstd -o "$archive"; } ;;
      *.tar)              tar cvf "$archive" "$@" ;;
      *.zip)              zip -r "$archive" "$@" ;;
      *.7z)               if command -v 7zz &>/dev/null; then 7zz a "$archive" "$@"; else 7z a "$archive" "$@"; fi ;;
      *.gz)               gzip -k -c "$1" > "$archive" ;;
      *.bz2)              bzip2 -k -c "$1" > "$archive" ;;
      *.zst)              zstd -k "$1" -o "$archive" ;;
      *)
        printf "\033[31m✖ Cannot pack '%s' — unsupported archive extension.\033[0m\n" "$archive" >&2
        printf "Supported: .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .tar.zst, .tar, .zip, .7z, .gz, .bz2, .zst\n" >&2
        return 1
        ;;
    esac
    rc=$?
  fi

  if [ $rc -eq 0 ] && [ -f "$archive" ]; then
    local sz
    sz=$(du -h "$archive" 2>/dev/null | awk '{print $1}')
    printf "\033[32m✔ Created archive:\033[0m \033[1m%s\033[0m (%s)\n" "$archive" "${sz:-done}"
  fi
  return $rc
}

# Cross-Platform Persistent Desktop & Terminal Notification
# Usage:
#   notify "Build finished!"
#   notify "Tests failed!" "Test Suite"
#   notify -b "Quick banner only"
#   npm run build && notify "Build succeeded!" || notify "Build failed!" "Error"
notify() {
  local banner_only=false
  if [ "$1" = "-b" ] || [ "$1" = "--banner" ]; then
    banner_only=true
    shift
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mnotify\033[0m (alias: \033[1malert\033[0m) — Persistent desktop & terminal notification (macOS, Linux, WSL)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  notify <message> [title]      Persistent alert that stays on screen until dismissed\n"
    printf "  notify -b <message> [title]   Transient corner banner only\n"
    return 0
  fi

  local msg="${1:-Command finished}"
  local title="${2:-Terminal}"

  # Terminal emulator desktop notification (Ghostty, WezTerm, Kitty, iTerm2 via OSC 777 & OSC 9)
  if [ -t 1 ]; then
    printf '\e]777;notify;%s;%s\e\\' "$title" "$msg" 2>/dev/null
    printf '\e]9;%s\a' "$msg" 2>/dev/null
  fi

  # 1. macOS: Persistent non-blocking floating alert + Notification Center banner + chime.
  # Passes $title and $msg via `on run argv` so quotes/backslashes in command strings never break AppleScript.
  if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"' -e 'end run' -- "$title" "$msg" 2>/dev/null || \
      osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' -- "$title" "$msg" 2>/dev/null || true
    if [ "$banner_only" = false ] && [ -t 1 ] && [ -z "$CI" ] && [ "$title" != "dottest" ]; then
      osascript -e 'on run argv' -e 'display alert (item 1 of argv) message (item 2 of argv) as informational buttons {"Dismiss"} default button "Dismiss"' -e 'end run' -- "$title" "$msg" &>/dev/null &!
    fi
    if [ -t 1 ] && [ "$title" != "dottest" ] && [ -f "/System/Library/Sounds/Glass.aiff" ]; then
      afplay "/System/Library/Sounds/Glass.aiff" &>/dev/null &!
    fi

  # 2. Linux: Persistent desktop notification (-u critical stays pinned until clicked/dismissed)
  elif command -v notify-send &>/dev/null; then
    if [ "$banner_only" = true ]; then
      notify-send "$title" "$msg" 2>/dev/null || true
    else
      notify-send -u critical "$title" "$msg" 2>/dev/null || notify-send "$title" "$msg" 2>/dev/null || true
    fi

  # 3. WSL: Persistent Windows 10/11 Toast Notification (scenario="reminder" stays until dismissed)
  # Passes title/message via environment variables so quotes or `$` never cause PowerShell injection.
  elif command -v powershell.exe &>/dev/null; then
    NOTIFY_TITLE="$title" NOTIFY_MSG="$msg" WSLENV="${WSLENV:+$WSLENV:}NOTIFY_TITLE/u:NOTIFY_MSG/u" \
      powershell.exe -NoProfile -Command '
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $xml = [xml]$template.GetXml()
        $toastNode = $xml.SelectSingleNode("/toast")
        if ($toastNode -ne $null) { $toastNode.SetAttribute("scenario", "reminder") }
        $xml.GetElementsByTagName("text")[0].AppendChild($xml.CreateTextNode($env:NOTIFY_TITLE)) > $null
        $xml.GetElementsByTagName("text")[1].AppendChild($xml.CreateTextNode($env:NOTIFY_MSG)) > $null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Terminal").Show($toast)
      ' 2>/dev/null || true

  # 4. Universal Fallback: ASCII Terminal Bell
  else
    printf "\a"
  fi

  # Terminal status output
  if [ -t 1 ]; then
    printf "\033[1;38;2;203;166;247m󰂚 [%s]\033[0m %s\n" "$title" "$msg"
  fi
}

typeset -g AUTO_NOTIFY_ENABLED="${AUTO_NOTIFY_ENABLED:-true}"

# Automatic Desktop Notification for Long-Running Foreground Commands (>15s)
toggle-autonotify() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mtoggle-autonotify\033[0m (alias: \033[1mautonotify\033[0m) — Toggle desktop notifications for commands >%ss\n" "${AUTO_NOTIFY_THRESHOLD:-15}"
    return 0
  fi
  if [ "$AUTO_NOTIFY_ENABLED" = "true" ]; then
    AUTO_NOTIFY_ENABLED="false"
    printf "\033[33m󰂛 Auto-notify disabled\033[0m (long-running commands will not send desktop alerts)\n"
  else
    AUTO_NOTIFY_ENABLED="true"
    printf "\033[32m󰂚 Auto-notify enabled\033[0m (commands >%ss will send desktop alerts)\n" "${AUTO_NOTIFY_THRESHOLD:-15}"
  fi
}

if [[ -o interactive ]]; then
  zmodload zsh/datetime 2>/dev/null || true
  typeset -g _auto_notify_cmd=""
  typeset -g _auto_notify_start=0

  _auto_notify_preexec() {
    _auto_notify_cmd="$1"
    _auto_notify_start="${EPOCHSECONDS:-0}"
  }

  _auto_notify_precmd() {
    local exit_status=$?
    if [ "${AUTO_NOTIFY_ENABLED:-true}" = "true" ] && (( _auto_notify_start > 0 )) && [ -n "$_auto_notify_cmd" ] && [ -n "$EPOCHSECONDS" ]; then
      local elapsed=$(( EPOCHSECONDS - _auto_notify_start ))
      local threshold="${AUTO_NOTIFY_THRESHOLD:-15}"
      if (( elapsed >= threshold )); then
        # Extract first command token (stripping leading sudo/env/time)
        local -a words
        words=(${(z)_auto_notify_cmd})
        local first_word="${words[1]:t}"
        while [[ "$first_word" == (sudo|env|time|nohup|command|builtin) ]] && (( ${#words[@]} > 1 )); do
          shift words
          first_word="${words[1]:t}"
        done

        # Ignore interactive TUIs, editors, pagers, and FZF shell pickers
        case "$first_word" in
          nvim|vim|vi|nano|emacs|code|yazi|y|lazygit|lg|btop|htop|top|man|less|more|ssh|mosh|tmux|zellij|fzf|gl|gco|gstash|ga|gadd|gfile|gfh|gsearch|wt|gwtdel|gwtclean|gbclean|conf|dotbranch|.branch|.b|scratch|fa|aliases|fenv|cheath|cheat|fjq|port|fport|fkill|kp|fcon|dps|fssh|fpkg|fbrew|fsize|bigfiles|fknown|proj|fp|snip|npmr|bunr|pnpmr|sdiff|strdiff|lastout|watch|fg|bg)
            ;;
          *)
            local mins=$(( elapsed / 60 ))
            local secs=$(( elapsed % 60 ))
            local dur_str="${secs}s"
            (( mins > 0 )) && dur_str="${mins}m ${secs}s"
            local short_cmd="${_auto_notify_cmd[1,48]}"
            if (( exit_status == 0 )); then
              notify "✔ ${short_cmd} (${dur_str})" "Command Completed" >/dev/null
            else
              notify "✖ ${short_cmd} (exit ${exit_status} after ${dur_str})" "Command Failed" >/dev/null
            fi
            ;;
        esac
      fi
    fi
    _auto_notify_cmd=""
    _auto_notify_start=0
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _auto_notify_preexec
  add-zsh-hook precmd _auto_notify_precmd
fi

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

  python3 - "$str1" "$str2" "$mode" << 'PYEOF'
import difflib
import re
import sys

a, b, mode = sys.argv[1], sys.argv[2], sys.argv[3]

C_RED_FG   = "\033[1;38;2;243;139;168m"
C_GREEN_FG = "\033[1;38;2;166;227;161m"
C_BLUE_FG  = "\033[1;38;2;137;180;250m"
C_DIM      = "\033[2m"
C_DEL      = "\033[1;38;2;243;139;168;48;2;69;39;50m"
C_ADD      = "\033[1;38;2;166;227;161;48;2;35;57;46m"
C_RST      = "\033[0m"

if a == b:
    print(f"{C_GREEN_FG}✔ Strings are identical{C_RST} {C_DIM}({len(a)} chars){C_RST}")
    sys.exit(0)

def fmt_ws(s: str, is_edge: bool = False) -> str:
    if not s:
        return s
    if s.strip(" \t") == "":
        return s.replace(" ", "·").replace("\t", "→")
    if is_edge:
        lstripped = s.lstrip(" \t")
        rstripped = s.rstrip(" \t")
        lead_len = len(s) - len(lstripped)
        trail_len = len(s) - len(rstripped)
        lead = s[:lead_len].replace(" ", "·").replace("\t", "→")
        trail = s[len(rstripped):].replace(" ", "·").replace("\t", "→") if trail_len > 0 else ""
        mid = s[lead_len:len(s) - trail_len]
        return lead + mid + trail
    return s

def tokenize(s: str):
    if mode == "word":
        return re.findall(r"\S+|\s+", s)
    return list(s)

def diff_line(la: str, lb: str):
    ta, tb = tokenize(la), tokenize(lb)
    sm = difflib.SequenceMatcher(None, ta, tb)
    old_p, new_p, inl_p = [], [], []
    opcodes = sm.get_opcodes()
    for idx, (tag, i1, i2, j1, j2) in enumerate(opcodes):
        sa = "".join(ta[i1:i2])
        sb = "".join(tb[j1:j2])
        edge_a = (i1 == 0 or i2 == len(ta))
        edge_b = (j1 == 0 or j2 == len(tb))
        if tag == "equal":
            old_p.append(sa)
            new_p.append(sb)
            inl_p.append(sa)
        elif tag == "delete":
            fa = fmt_ws(sa, edge_a)
            old_p.append(f"{C_DEL}{fa}{C_RST}")
            inl_p.append(f"{C_DEL}{fa}{C_RST}")
        elif tag == "insert":
            fb = fmt_ws(sb, edge_b)
            new_p.append(f"{C_ADD}{fb}{C_RST}")
            inl_p.append(f"{C_ADD}{fb}{C_RST}")
        elif tag == "replace":
            fa = fmt_ws(sa, edge_a)
            fb = fmt_ws(sb, edge_b)
            old_p.append(f"{C_DEL}{fa}{C_RST}")
            new_p.append(f"{C_ADD}{fb}{C_RST}")
            inl_p.append(f"{C_DEL}{fa}{C_RST}{C_ADD}{fb}{C_RST}")
    return "".join(old_p), "".join(new_p), "".join(inl_p), sm.ratio()

lines_a = a.splitlines() or [""]
lines_b = b.splitlines() or [""]
single_line = len(lines_a) == 1 and len(lines_b) == 1

sm_lines = difflib.SequenceMatcher(None, lines_a, lines_b)
for tag, i1, i2, j1, j2 in sm_lines.get_opcodes():
    if tag == "equal":
        for l in lines_a[i1:i2]:
            print(f"    {C_DIM}{l}{C_RST}")
    elif tag == "delete":
        for l in lines_a[i1:i2]:
            print(f"  {C_RED_FG}-{C_RST} {C_DEL}{fmt_ws(l, True)}{C_RST}")
    elif tag == "insert":
        for l in lines_b[j1:j2]:
            print(f"  {C_GREEN_FG}+{C_RST} {C_ADD}{fmt_ws(l, True)}{C_RST}")
    elif tag == "replace":
        ca, cb = lines_a[i1:i2], lines_b[j1:j2]
        pairs = min(len(ca), len(cb))
        for k in range(pairs):
            o, n, inl, ratio = diff_line(ca[k], cb[k])
            if single_line or ratio >= 0.45:
                print(f"  {C_RED_FG}-{C_RST} {o}")
                print(f"  {C_GREEN_FG}+{C_RST} {n}")
                print(f"  {C_BLUE_FG}Δ{C_RST} {inl}")
            else:
                print(f"  {C_RED_FG}-{C_RST} {C_DEL}{fmt_ws(ca[k], True)}{C_RST}")
                print(f"  {C_GREEN_FG}+{C_RST} {C_ADD}{fmt_ws(cb[k], True)}{C_RST}")
        for l in ca[pairs:]:
            print(f"  {C_RED_FG}-{C_RST} {C_DEL}{fmt_ws(l, True)}{C_RST}")
        for l in cb[pairs:]:
            print(f"  {C_GREEN_FG}+{C_RST} {C_ADD}{fmt_ws(l, True)}{C_RST}")
PYEOF
}

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

# Internal helper: enumerate installed packages across Homebrew, Mise, and Linux package managers
# Output format: <manager>\t<package>\t<version>
_fpkg_list() {
  if command -v brew &>/dev/null; then
    brew list --formula --versions 2>/dev/null | awk 'NF>=2 {printf "brew\t%s\t%s\n", $1, $2}'
    brew list --cask --versions 2>/dev/null | awk 'NF>=2 {printf "cask\t%s\t%s\n", $1, $2}'
  fi
  if command -v mise &>/dev/null; then
    mise ls --current 2>/dev/null | awk 'NF>=2 {printf "mise\t%s\t%s\n", $1, $2}'
  fi
  if ! command -v brew &>/dev/null; then
    if command -v dpkg-query &>/dev/null; then
      dpkg-query -W -f='apt\t${Package}\t${Version}\n' 2>/dev/null
    elif command -v pacman &>/dev/null; then
      pacman -Q 2>/dev/null | awk 'NF>=2 {printf "pacman\t%s\t%s\n", $1, $2}'
    elif command -v rpm &>/dev/null; then
      rpm -qa --qf 'dnf\t%{NAME}\t%{VERSION}\n' 2>/dev/null | sort
    fi
  fi
}

# Interactive Package Inspector & Manager (fpkg / fbrew)
# Browse installed Homebrew, Mise, and Linux system packages in modal-Vim FZF
# Usage:
#   fpkg / fbrew       -> Browse all installed packages with info & dependency preview
#   fpkg <query>       -> Open filtered by <query> (e.g. fpkg ripgrep, fbrew node)
#   fpkg -l, --list    -> Print tab-separated table (<manager>\t<name>\t<version>)
#   Keys: enter = print info, u = upgrade, x = uninstall, o = open homepage, y = copy name
fpkg() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;249;226;175mfpkg\033[0m (alias: \033[1mfbrew\033[0m) — Interactive modal-Vim package inspector (Homebrew, Mise & Linux)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fpkg / fbrew       Browse installed packages with live info & dependency preview\n"
    printf "  fpkg <query>       Open pre-filtered by <query>\n"
    printf "  fpkg -l, --list    Print tab-separated catalog of installed packages\n"
    printf "  Enter              Print full package metadata & dependency info\n"
    printf "  u                  Upgrade selected package(s)\n"
    printf "  x                  Uninstall selected package(s)\n"
    printf "  o                  Open package homepage in browser\n"
    printf "  y                  Copy package name(s) to clipboard\n"
    return 0
  fi

  local list_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  fi

  local query="$*"
  local rows
  rows="$(_fpkg_list)"
  if [[ -z "$rows" ]]; then
    printf "\033[33mNo installed packages found (brew, mise, apt, pacman, dnf).\033[0m\n" >&2
    return 1
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
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' '{
    mgr = $1; pkg = $2; ver = $3;
    if (mgr == "brew")      m_col = sprintf("\033[38;2;249;226;175m%-8s\033[0m", mgr);
    else if (mgr == "cask") m_col = sprintf("\033[38;2;245;194;231m%-8s\033[0m", mgr);
    else if (mgr == "mise") m_col = sprintf("\033[38;2;203;166;247m%-8s\033[0m", mgr);
    else                    m_col = sprintf("\033[38;2;137;180;250m%-8s\033[0m", mgr);
    printf "%s\t\033[1m%-28s\033[0m\t\033[38;2;166;227;161m%s\033[0m\t%s\t%s\n", m_col, pkg, ver, mgr, pkg
  }')

  local hdr="  j/k: move │ space: select │ /: search │ enter: info │ u: upgrade │ x: uninstall │ o: home │ y: copy │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "📦 Packages > " "$hdr" "info" "space,u,x,o,y" "$query" "space:toggle+down"

  local preview_cmd='
    mgr={4}; pkg={5}
    case "$mgr" in
      brew)
        brew info "$pkg" 2>/dev/null
        echo ""
        brew deps --tree --installed "$pkg" 2>/dev/null
        ;;
      cask)
        brew info --cask "$pkg" 2>/dev/null
        ;;
      mise)
        mise tool "$pkg" 2>/dev/null
        echo ""
        mise ls "$pkg" 2>/dev/null
        ;;
      apt)
        dpkg -s "$pkg" 2>/dev/null
        ;;
      pacman)
        pacman -Qi "$pkg" 2>/dev/null
        ;;
      dnf)
        rpm -qi "$pkg" 2>/dev/null
        ;;
    esac
  '

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --multi \
    --height=~60% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:yellow,pointer:bold:green,marker:bold:yellow" \
    --preview="$preview_cmd" \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selection" || return 0

  local -a pkgs=()
  local c1 c2 c3 mgr pkg
  while IFS=$'\t' read -r c1 c2 c3 mgr pkg; do
    [[ -n "$pkg" ]] && pkgs+=("$pkg")
    case "$key" in
      u)
        printf "\033[1;36m➜ Upgrading %s (%s)...\033[0m\n" "$pkg" "$mgr"
        case "$mgr" in
          brew)   brew upgrade "$pkg" ;;
          cask)   brew upgrade --cask "$pkg" ;;
          mise)   mise upgrade "$pkg" ;;
          apt)    sudo apt-get install --only-upgrade -y "$pkg" ;;
          pacman) sudo pacman -S "$pkg" ;;
          dnf)    sudo dnf upgrade -y "$pkg" ;;
        esac
        ;;
      x)
        printf "\033[1;31m➜ Uninstalling %s (%s)...\033[0m\n" "$pkg" "$mgr"
        case "$mgr" in
          brew)   brew uninstall "$pkg" ;;
          cask)   brew uninstall --cask "$pkg" ;;
          mise)   mise uninstall "$pkg" ;;
          apt)    sudo apt-get remove -y "$pkg" ;;
          pacman) sudo pacman -R "$pkg" ;;
          dnf)    sudo dnf remove -y "$pkg" ;;
        esac
        ;;
      o)
        case "$mgr" in
          brew) brew home "$pkg" ;;
          cask) brew home --cask "$pkg" ;;
          apt)
            local url
            url="$(dpkg -s "$pkg" 2>/dev/null | awk '/^Homepage:/ {print $2; exit}')"
            [[ -n "$url" ]] && open "$url"
            ;;
        esac
        ;;
      "")
        case "$mgr" in
          brew)   brew info "$pkg" ;;
          cask)   brew info --cask "$pkg" ;;
          mise)   mise tool "$pkg" ;;
          apt)    dpkg -s "$pkg" ;;
          pacman) pacman -Qi "$pkg" ;;
          dnf)    rpm -qi "$pkg" ;;
        esac
        ;;
    esac
  done <<< "$selected_lines"

  if [[ "$key" == "y" ]] && (( ${#pkgs[@]} > 0 )); then
    _copy_or_print "${(j: :)pkgs}" "package name(s): ${(j: :)pkgs}"
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
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' '{
    kind = $1; target = $2; meta = $3;
    if (kind == "socket") k_col = sprintf("\033[38;2;166;227;161m%-12s\033[0m", "⚡ socket");
    else                  k_col = sprintf("\033[38;2;137;180;250m%-12s\033[0m", "🔑 host");
    printf "%s\t\033[1m%-32s\033[0m\t\033[2m%s\033[0m\t%s\t%s\n", k_col, target, meta, kind, target
  }')

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

# Cross-Platform Network, DNS, Tunnel & Latency Diagnostic Card (fnet / netinfo)
# Works across macOS, Linux, and WSL
fnet() {
  local fetch_public=false run_ping=true
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;137;180;250mfnet\033[0m (alias: \033[1mnetinfo\033[0m) — Cross-platform network, DNS, VPN & latency diagnostic card\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  fnet                 Show active interface, LAN IP, gateway, DNS, VPN tunnels & ping\n"
        printf "  fnet -p, --public    Also query external public IP address\n"
        printf "  fnet --no-ping       Skip 1.1.1.1 latency probe\n"
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
  printf "\033[1;38;2;137;180;250m│\033[0m  \033[1m🌐 Network & Connectivity Diagnostic (fnet)\033[0m           \033[1;38;2;137;180;250m│\033[0m\n"
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

# File Checksum & Integrity Verifier (fhash / hashfile)
# Computes MD5, SHA-1, SHA-256, and SHA-512 in a single pass and compares against an expected
# hash (or auto-detects a hex digest in the system clipboard).
# Usage:
#   fhash <file> [expected_hash]
#   fhash -c <file>              -> Copy SHA-256 hash to clipboard
fhash() {
  local copy_sha256=false
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;249;226;175mfhash\033[0m (alias: \033[1mhashfile\033[0m) — Multi-digest file checksum & integrity verifier\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  fhash <file>                 Compute MD5, SHA-1, SHA-256 & SHA-512 (auto-checks clipboard digest)\n"
        printf "  fhash <file> <expected_hex>  Verify file against expected checksum\n"
        printf "  fhash -c, --copy <file>      Also copy SHA-256 digest to clipboard\n"
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
    printf "\033[33mUsage: fhash [-c] <file> [expected_hash]\033[0m\n" >&2
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
  out="$(python3 - "$file" "$expected" "$expected_source" <<'PYEOF'
import hashlib
import os
import sys

filepath, expected, source = sys.argv[1], sys.argv[2].strip().lower(), sys.argv[3]
# Allow "sha256:..." prefix in expected hash
if ":" in expected:
    expected = expected.split(":", 1)[1].strip()

h_md5 = hashlib.md5()
h_sha1 = hashlib.sha1()
h_sha256 = hashlib.sha256()
h_sha512 = hashlib.sha512()

with open(filepath, "rb") as f:
    while chunk := f.read(1024 * 1024):
        h_md5.update(chunk)
        h_sha1.update(chunk)
        h_sha256.update(chunk)
        h_sha512.update(chunk)

digests = [
    ("MD5", h_md5.hexdigest()),
    ("SHA-1", h_sha1.hexdigest()),
    ("SHA-256", h_sha256.hexdigest()),
    ("SHA-512", h_sha512.hexdigest()),
]

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE  = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_RED   = "\033[1;38;2;243;139;168m"
C_DIM   = "\033[2m"
C_RST   = "\033[0m"

sz = os.path.getsize(filepath)
print(f"{C_MAUVE}📄 {os.path.basename(filepath)}{C_RST} {C_DIM}({sz:,} bytes){C_RST}")
matched_algo = None
for name, d in digests:
    mark = ""
    if expected and d == expected:
        matched_algo = name
        mark = f" {C_GREEN}✔ MATCH{C_RST}"
    print(f"  {C_BLUE}{name:<8}{C_RST} {d}{mark}")

print(f"__SHA256__:{h_sha256.hexdigest()}")
if expected:
    if matched_algo:
        print(f"\n{C_GREEN}✔ Checksum verified ({matched_algo} matched {source}){C_RST}")
        sys.exit(0)
    else:
        print(f"\n{C_RED}✖ Checksum MISMATCH against {source}: {expected}{C_RST}")
        sys.exit(1)
PYEOF
  )" || rc=$?

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


