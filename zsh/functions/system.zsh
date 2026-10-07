# Interactive TCP Port Inspector & Killer (port)
# Usage:
#   port             -> Interactive modal-Vim FZF browser of all listening TCP ports (Enter/x to kill)
#   port <number>    -> Inspect process listening on <number>
#   port -k <number> -> Kill process listening on <number>
port() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mport\033[0m — Inspect or kill processes listening on TCP ports (macOS & Linux)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  port               Interactive modal-Vim FZF browser of listening ports\n"
    printf "  port <port>        Show process bound to <port>\n"
    printf "  port -k <port>     Terminate process bound to <port>\n"
    return 0
  fi

  local kill_mode=false
  if [ "$1" = "-k" ] || [ "$1" = "--kill" ]; then
    kill_mode=true
    shift
  fi

  # Helper to list listening ports across macOS (lsof) and Linux (lsof or ss)
  _list_listening_ports() {
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

  # Direct port argument provided
  if [ -n "$1" ]; then
    local target_port="${1#:}"
    if [ "$kill_mode" = true ]; then
      local pids=()
      if command -v lsof &>/dev/null; then
        pids=($(lsof -t -i :"$target_port" 2>/dev/null))
      elif command -v fuser &>/dev/null; then
        pids=($(fuser "${target_port}/tcp" 2>/dev/null))
      fi
      if [ "${#pids[@]}" -eq 0 ]; then
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
  fi

  # No port specified: non-TTY or missing fzf prints table
  local rows
  rows="$(_list_listening_ports)"
  if [ -z "$rows" ]; then
    printf "\033[33mNo listening TCP ports found.\033[0m\n"
    return 0
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "\033[1;38;2;137;180;250m%-8s\t%-8s\t%-18s\t%s\033[0m\n" "PORT" "PID" "PROCESS" "ADDRESS"
    printf "%s\n" "$rows"
    return 0
  fi

  local selected
  selected=$(printf "%s\n" "$rows" | fzf \
    --delimiter='\t' \
    --multi \
    --height=~50% \
    --layout=reverse \
    --border=rounded \
    --disabled \
    --pointer="❯ " \
    --marker="✓ " \
    --prompt="🔌 Listening Ports > " \
    --header=$'  j/k: navigate │ space: select │ /: search │ enter/x: kill process │ q: quit\n  PORT    \tPID     \tPROCESS           \tADDRESS' \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:red,marker:bold:red" \
    --bind="start:unbind(esc)" \
    --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,space:toggle+down,x:accept" \
    --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,space,x,i,/)+change-prompt(🔍 Search Ports > )+change-header(  type to filter │ esc: normal mode │ enter: kill)+rebind(esc)" \
    --bind="i:enable-search+unbind(j,k,q,g,G,space,x,i,/)+change-prompt(🔍 Search Ports > )+change-header(  type to filter │ esc: normal mode │ enter: kill)+rebind(esc)" \
    --bind=$'esc:disable-search+rebind(j,k,q,g,G,space,x,i,/)+change-prompt(🔌 Listening Ports > )+change-header(  j/k: navigate │ space: select │ /: search │ enter/x: kill process │ q: quit\n  PORT    \tPID     \tPROCESS           \tADDRESS)+unbind(esc)' \
    --preview='pid=$(echo {2} | tr -d " "); if [ -n "$pid" ] && [ "$pid" != "-" ]; then ps -p "$pid" -o pid,ppid,user,%cpu,%mem,etime,command 2>/dev/null; echo ""; lsof -p "$pid" -iTCP -P -n 2>/dev/null | head -n 20; fi' \
    --preview-window='right:55%:wrap')

  [ -z "$selected" ] && return 0

  while IFS=$'\t' read -r p_col pid_col proc_col addr_col; do
    local p_clean="${p_col// /}"
    local pid_clean="${pid_col// /}"
    if [ -n "$pid_clean" ] && [ "$pid_clean" != "-" ]; then
      if kill -15 "$pid_clean" 2>/dev/null || kill -9 "$pid_clean" 2>/dev/null; then
        printf "  \033[32m✔\033[0m Killed \033[1m%s\033[0m (PID %s) on port \033[1;36m%s\033[0m\n" "${proc_col// /}" "$pid_clean" "$p_clean"
      else
        printf "  \033[31m✖\033[0m Failed to kill PID %s on port %s\n" "$pid_clean" "$p_clean" >&2
      fi
    fi
  done <<< "$selected"
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

  _list_user_procs() {
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

  local rows
  rows="$(_list_user_procs)"
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
  local fzf_mode_flags=()
  if [ -z "$query" ]; then
    fzf_mode_flags=(
      "--disabled"
      "--bind=start:unbind(esc)"
      "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,space:toggle+down"
      "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,space,x,i,/)+change-prompt(🔍 Search Procs > )+change-header(  type to filter │ esc: normal mode │ enter: SIGTERM)+rebind(esc)"
      "--bind=i:enable-search+unbind(j,k,q,g,G,space,x,i,/)+change-prompt(🔍 Search Procs > )+change-header(  type to filter │ esc: normal mode │ enter: SIGTERM)+rebind(esc)"
      "--bind=esc:disable-search+rebind(j,k,q,g,G,space,x,i,/)+change-prompt(⚡ Processes > )+change-header($hdr)+unbind(esc)"
    )
  else
    fzf_mode_flags=(
      "--query=$query"
      "--bind=space:toggle+down"
    )
  fi

  local selection
  selection=$(printf "%s\n" "$rows" | fzf \
    --delimiter='\t' \
    --multi \
    --height=~55% \
    --layout=reverse \
    --border=rounded \
    --pointer="❯ " \
    --marker="✓ " \
    --prompt="⚡ Processes > " \
    --header="$hdr" \
    --color="header:italic:dim,prompt:bold:red,pointer:bold:red,marker:bold:yellow" \
    "${fzf_mode_flags[@]}" \
    --preview='pid=$(echo {1} | tr -d " "); if [ -n "$pid" ]; then ps -p "$pid" -o pid,ppid,user,%cpu,%mem,etime,command 2>/dev/null; echo ""; if command -v lsof &>/dev/null; then lsof -p "$pid" -i -P -n 2>/dev/null | head -n 15; fi; fi' \
    --preview-window='right:50%:wrap' \
    --expect="x")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_lines
  selected_lines=$(echo "$selection" | sed '1d')
  [ -z "$selected_lines" ] && return 0

  local sig="-15"
  local sig_name="SIGTERM (-15)"
  if [ "$key" = "x" ]; then
    sig="-9"
    sig_name="SIGKILL (-9)"
  fi

  while IFS=$'\t' read -r pid_col cpu_col mem_col proc_col cmd_col; do
    local pid_clean="${pid_col// /}"
    local proc_clean="${proc_col// /}"
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
    printf "\033[33mNo containers found (%s).\033[0m\n" "$(basename "$rt")"
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
  local fzf_mode_flags=()
  if [ -z "$query" ]; then
    fzf_mode_flags=(
      "--disabled"
      "--bind=start:unbind(esc)"
      "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,space:toggle+down"
      "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,space,l,s,r,x,i,/)+change-prompt(🔍 Search Containers > )+change-header(  type to filter │ esc: normal mode │ enter: follow logs)+rebind(esc)"
      "--bind=i:enable-search+unbind(j,k,q,g,G,space,l,s,r,x,i,/)+change-prompt(🔍 Search Containers > )+change-header(  type to filter │ esc: normal mode │ enter: follow logs)+rebind(esc)"
      "--bind=esc:disable-search+rebind(j,k,q,g,G,space,l,s,r,x,i,/)+change-prompt(🐳 Containers ($(basename "$rt")) > )+change-header($hdr)+unbind(esc)"
    )
  else
    fzf_mode_flags=(
      "--query=$query"
      "--bind=space:toggle+down"
    )
  fi

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter='\t' \
    --multi \
    --height=~60% \
    --layout=reverse \
    --border=rounded \
    --pointer="❯ " \
    --marker="✓ " \
    --prompt="🐳 Containers ($(basename "$rt")) > " \
    --header="$hdr" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:blue,marker:bold:yellow" \
    "${fzf_mode_flags[@]}" \
    --bind="ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up" \
    --preview="cid=\$(echo {1} | sed 's/\x1b\[[0-9;]*m//g' | tr -d ' '); [ -n \"\$cid\" ] && '$rt' logs --tail 60 \"\$cid\" 2>&1" \
    --preview-window='right:55%:wrap' \
    --expect="l,s,r,x")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_lines
  selected_lines=$(echo "$selection" | sed '1d')
  [ -z "$selected_lines" ] && return 0

  local -a cids cnames
  while IFS=$'\t' read -r id_col name_col rest; do
    local cid cname
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
  local fzf_mode_flags=()
  if [ -z "$query" ]; then
    fzf_mode_flags=(
      "--disabled"
      "--bind=start:unbind(esc)"
      "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort"
      "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,y,e,i,/)+change-prompt(🔍 Search SSH Hosts > )+change-header(  type to filter │ esc: normal mode │ enter: connect)+rebind(esc)"
      "--bind=i:enable-search+unbind(j,k,q,g,G,y,e,i,/)+change-prompt(🔍 Search SSH Hosts > )+change-header(  type to filter │ esc: normal mode │ enter: connect)+rebind(esc)"
      "--bind=esc:disable-search+rebind(j,k,q,g,G,y,e,i,/)+change-prompt(🔐 SSH Hosts > )+change-header($hdr)+unbind(esc)"
    )
  else
    fzf_mode_flags=(
      "--query=$query"
    )
  fi

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
    --layout=reverse \
    --border=rounded \
    --pointer="❯ " \
    --prompt="🔐 SSH Hosts > " \
    --header="$hdr" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    "${fzf_mode_flags[@]}" \
    --preview="$preview_cmd" \
    --preview-window='right:50%:wrap' \
    --expect="y,e")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_line
  selected_line=$(echo "$selection" | sed '1d' | head -n1)
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
      if (( $+functions[copy] )); then
        printf "%s" "$target_str" | copy
        printf "\033[32m✔ Copied SSH target to clipboard: %s\033[0m\n" "$target_str"
      else
        printf "%s\n" "$target_str"
      fi
      ;;
    e)
      local ln
      ln=$(grep -nE "^[[:space:]]*[Hh]ost[[:space:]]+${host_alias}([[:space:]]|$)" "$ssh_cfg" 2>/dev/null | head -n1 | cut -d: -f1)
      local editor="${EDITOR:-nvim}"
      command -v "$editor" &>/dev/null || editor="nano"
      if [ -n "$ln" ] && [[ "$editor" == *vim* ]]; then
        "$editor" "+$ln" "$ssh_cfg"
      else
        "$editor" "$ssh_cfg"
      fi
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

# Cross-Platform Clipboard Helpers (macOS, Linux Wayland, Linux X11, WSL)
copy() {
  if command -v pbcopy &>/dev/null; then
    pbcopy "$@"
  elif command -v wl-copy &>/dev/null; then
    wl-copy "$@"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard "$@"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --input "$@"
  elif command -v clip.exe &>/dev/null; then
    clip.exe "$@"
  elif [ -n "$TMUX" ]; then
    tmux load-buffer -
  else
    printf "\033[33mNo clipboard utility found (pbcopy, wl-copy, xclip, clip.exe)\033[0m\n" >&2
    return 1
  fi
}

paste() {
  if command -v pbpaste &>/dev/null; then
    pbpaste "$@"
  elif command -v wl-paste &>/dev/null; then
    wl-paste "$@"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard -o "$@"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --output "$@"
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command Get-Clipboard "$@"
  else
    printf "\033[33mNo clipboard utility found (pbpaste, wl-paste, xclip, powershell.exe)\033[0m\n" >&2
    return 1
  fi
}

# Universal Archive Extractor (extract / x)
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
    *.7z)               7z x "$file" ;;
    *.zst)              zstd -d "$file" ;;
    *)
      printf "\033[31m✖ Cannot extract '%s' — unsupported extension.\033[0m\n" "$file" >&2
      return 1
      ;;
  esac
}

# Cross-Platform Desktop & Terminal Notification
# Usage:
#   notify "Build finished!"
#   notify "Tests failed!" "Test Suite"
#   npm run build && notify "Build succeeded!" || notify "Build failed!" "Error"
notify() {
  local msg="${1:-Command finished}"
  local title="${2:-Terminal}"

  # Terminal emulator desktop notification (Ghostty, WezTerm, Kitty, iTerm2 via OSC 777 & OSC 9)
  if [ -t 1 ]; then
    printf '\e]777;notify;%s;%s\e\\' "$title" "$msg" 2>/dev/null
    printf '\e]9;%s\a' "$msg" 2>/dev/null
  fi

  # 1. macOS: Native Notification Center banner + subtle glass chime
  if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    osascript -e "display notification \"$msg\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || \
      osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
    if [ -t 1 ] && [ -f "/System/Library/Sounds/Glass.aiff" ]; then
      afplay "/System/Library/Sounds/Glass.aiff" &>/dev/null &!
    fi

  # 2. Linux: Desktop notification daemon (libnotify / notify-send)
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$msg" 2>/dev/null || true

  # 3. WSL: Native Windows 10/11 Toast Notification via PowerShell
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command "
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
      \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
      \$xml = [xml]\$template.GetXml()
      \$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('$title')) > \$null
      \$xml.GetElementsByTagName('text')[1].AppendChild(\$xml.CreateTextNode('$msg')) > \$null
      \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Terminal').Show(\$toast)
    " 2>/dev/null || true

  # 4. Universal Fallback: ASCII Terminal Bell
  else
    printf "\a"
  fi

  # Terminal status output
  if [ -t 1 ]; then
    printf "\033[1;38;2;203;166;247m󰂚 [%s]\033[0m %s\n" "$title" "$msg"
  fi
}

# Automatic Desktop Notification for Long-Running Foreground Commands (>30s)
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
    if (( _auto_notify_start > 0 )) && [ -n "$_auto_notify_cmd" ] && [ -n "$EPOCHSECONDS" ]; then
      local elapsed=$(( EPOCHSECONDS - _auto_notify_start ))
      local threshold="${AUTO_NOTIFY_THRESHOLD:-30}"
      if (( elapsed >= threshold )); then
        # Extract first command token (stripping leading sudo/env/time)
        local -a words
        words=(${(z)_auto_notify_cmd})
        local first_word="${words[1]:t}"
        while [[ "$first_word" == (sudo|env|time|nohup|command|builtin) ]] && (( ${#words[@]} > 1 )); do
          shift words
          first_word="${words[1]:t}"
        done

        # Ignore interactive TUIs, editors, pagers, and shell pickers
        case "$first_word" in
          nvim|vim|vi|nano|emacs|code|yazi|y|lazygit|lg|btop|htop|top|man|less|more|ssh|mosh|tmux|zellij|fzf|gl|gco|gstash|wt|gwtdel|gwtclean|gbclean|conf|dotbranch|.branch|.b|scratch|fa|aliases|port|watch|fg|bg)
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

# String & Snippet Diff Helper (sdiff / strdiff)
# Usage:
#   sdiff "str1" "str2"       -> Character-level inline diff in terminal
#   sdiff -w "str1" "str2"    -> Word-level inline diff in terminal
#   sdiff "str2"              -> Compare system clipboard against "str2"
#   sdiff [-i] ["s1" "s2"]    -> Open side-by-side scratch buffers in nvim -d
sdiff() {
  local mode="char"
  local interactive=false
  local args=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        printf "\033[1;38;2;137;180;250msdiff\033[0m (alias: \033[1mstrdiff\033[0m) — Compare strings, clipboard, or snippets\n\n"
        printf "\033[1mUsage:\033[0m\n"
        printf "  sdiff <str1> <str2>        Character-level inline diff in terminal\n"
        printf "  sdiff -w <str1> <str2>     Word-level inline diff in terminal\n"
        printf "  sdiff <str2>               Compare clipboard content against <str2>\n"
        printf "  sdiff [-i] [str1] [str2]   Interactive side-by-side diff in nvim -d\n\n"
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
    if ! str1="$(paste 2>/dev/null)"; then
      printf "\033[31m✖ Could not read from clipboard. Provide two strings: sdiff <str1> <str2>\033[0m\n" >&2
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
    tmp_left="$(mktemp -t "sdiff-left.XXXXXX")"
    tmp_right="$(mktemp -t "sdiff-right.XXXXXX")"
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

