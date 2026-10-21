# ==============================================================================
# Process, Port, Container & SSH Host Browsers (`zsh/functions/process.zsh`)
# ==============================================================================
# Interactive FZF tools for inspecting and managing TCP ports (`port`), running
# processes (`fkill`), Podman/Docker containers (`fcon`), and SSH hosts (`fssh`).

# Internal helper: list listening TCP ports across macOS (lsof) and Linux (lsof or ss)
_port_list_listening() {
  if command -v lsof &>/dev/null; then
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1 {
      split($9, a, ":");
      p = a[length(a)];
      proc = $1;
      gsub(/\\x20/, " ", proc);
      if (length(proc) > 18) proc = substr(proc, 1, 15) "...";
      key = p ":" $2;
      if (!seen[key]++) {
        printf "%-8s\t%-8s\t%-18s\t%s\n", p, $2, proc, $9
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
      if (length(proc) > 18) proc = substr(proc, 1, 15) "...";
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
        h_disp = host;
        if (length(h_disp) > 24) h_disp = substr(h_disp, 1, 21) "...";
        hn = (hostname != "" ? hostname : "-");
        if (length(hn) > 30) hn = substr(hn, 1, 27) "...";
        u = (user != "" ? user : "-");
        if (length(u) > 16) u = substr(u, 1, 13) "...";
        p = (port != "" ? port : "22");
        printf "\033[1;36m%-24s\033[0m\t%-30s\t%-16s\t%s\n", h_disp, hn, u, p
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
