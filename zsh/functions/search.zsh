# Search Aliases & Functions (fa / aliases)

fa() {
  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local query=""
  local print_mode=false

  # Check flags: -p / --print or non-tty outputs raw text instead of interactive fzf
  if [ "$1" = "-p" ] || [ "$1" = "--print" ]; then
    print_mode=true
    shift
    query="$*"
  elif ! [ -t 1 ]; then
    print_mode=true
    query="$*"
  else
    query="$*"
  fi

  _gen_list() {
    # 1. Custom dotfiles functions
    for fn in take up tree lt groot gmain conf dotbranch clone port fkill fcon fssh gsearch wt gwtnew gwts gwtdel gwtclean gbclean gstash ga gfile y copy paste scratch extract npmr bunr pnpmr toggle-autols fa fenv cheath notify gl gco sdiff; do
      if (( $+functions[$fn] )); then
        printf "function\t%-18s\t(shell function)\n" "$fn"
      fi
    done

    # 2. Standalone dotfiles bin tools
    if [ -d "$dot_dir/bin" ]; then
      for b in "$dot_dir/bin/"*; do
        [ -x "$b" ] && printf "tool\t%-18s\t%s\n" "$(basename "$b")" "(CLI utility in ~/.local/bin)"
      done
    fi

    # 3. Active shell aliases
    alias | while IFS='=' read -r name val; do
      printf "alias\t%-18s\t%s\n" "$name" "$val"
    done
  }

  if [ "$print_mode" = true ]; then
    # Text-filtered output for pipes or when -p is specified
    if [ -n "$query" ]; then
      _gen_list | awk -F'\t' -v q="$query" 'tolower($2) ~ tolower(q) {
        if ($1 == "alias")    printf "\033[38;2;137;180;250m[%s]\033[0m \033[1;38;2;203;166;247m%-18s\033[0m %s\n", $1, $2, $3
        if ($1 == "function") printf "\033[38;2;166;227;161m[%s]\033[0m \033[1;38;2;203;166;247m%-18s\033[0m %s\n", $1, $2, $3
        if ($1 == "tool")     printf "\033[38;2;249;226;175m[%s]\033[0m \033[1;38;2;203;166;247m%-18s\033[0m %s\n", $1, $2, $3
      }'
    else
      _gen_list
    fi
  elif command -v fzf &>/dev/null; then
    local fzf_mode_flags=()
    if [ -z "$query" ]; then
      fzf_mode_flags=(
        "--disabled"
        "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept"
        "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: paste)+rebind(esc)"
        "--bind=i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: paste)+rebind(esc)"
        "--bind=esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(⚡ Aliases & Functions > )+change-header(  j/k: navigate │ /: search │ enter: paste │ q: quit)+unbind(esc)"
        "--bind=start:unbind(esc)"
        "--header=  j/k: navigate │ /: search │ enter: paste │ q: quit"
        "--prompt=⚡ Aliases & Functions > "
      )
    else
      fzf_mode_flags=(
        "--query=$query"
        "--header=  enter: paste │ esc: quit"
        "--prompt=🔍 Search Aliases & Functions > "
      )
    fi

    local selected
    selected=$(_gen_list | fzf \
      --delimiter='\t' \
      --nth=2 \
      --with-nth=1,2,3 \
      --height=~45% \
      --layout=reverse \
      --border=rounded \
      --pointer="❯ " \
      --color="header:italic:dim,prompt:bold:magenta,pointer:bold:magenta" \
      "${fzf_mode_flags[@]}" \
      --preview='which {2} 2>/dev/null | if command -v bat &>/dev/null; then bat -l zsh --color=always --style=plain; else cat; fi' \
      --preview-window='right:55%:wrap')

    if [ -n "$selected" ]; then
      local cmd
      cmd=$(echo "$selected" | awk -F'\t' '{print $2}' | xargs)
      print -z "$cmd "
    fi
  else
    _gen_list | awk -F'\t' -v q="$query" 'tolower($2) ~ tolower(q)'
  fi
}

# Interactive Environment Variable Inspector (fenv)
# Usage:
#   fenv               -> Browse all environment variables in modal-Vim FZF with smart PATH breakdown
#   fenv <query>       -> Open filtered by <query> (e.g. fenv PATH, fenv FZF)
#   Keys: enter/y = copy value, n = copy NAME=VALUE, e = edit export on prompt
fenv() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mfenv\033[0m — Interactive modal-Vim environment variable inspector\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fenv               Browse all environment variables\n"
    printf "  fenv <query>       Open pre-filtered by <query> (e.g. fenv PATH)\n"
    printf "  Enter / y          Copy variable value to clipboard\n"
    printf "  n                  Copy NAME=VALUE to clipboard\n"
    printf "  e                  Insert 'export NAME=...' onto command line\n"
    return 0
  fi

  local query="$*"

  _list_env_vars() {
    env | sort | awk -F'=' '
      /^[A-Za-z_][A-Za-z0-9_]*=/ {
        name = $1;
        val = substr($0, length(name) + 2);
        gsub(/\n/, " ", val);
        if (length(val) > 75) val = substr(val, 1, 72) "...";
        printf "\033[1;38;2;137;180;250m%-28s\033[0m\t%s\n", name, val
      }
    '
  }

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    if [ -n "$query" ]; then
      _list_env_vars | grep -i "$query"
    else
      _list_env_vars
    fi
    return 0
  fi

  local hdr="  j/k: navigate │ /: search │ enter/y: copy value │ n: copy KEY=VAL │ e: edit export │ q: quit"
  local fzf_mode_flags=()
  if [ -z "$query" ]; then
    fzf_mode_flags=(
      "--disabled"
      "--bind=start:unbind(esc)"
      "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort"
      "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,y,n,e,i,/)+change-prompt(🔍 Search Env > )+change-header(  type to filter │ esc: normal mode │ enter: copy value)+rebind(esc)"
      "--bind=i:enable-search+unbind(j,k,q,g,G,y,n,e,i,/)+change-prompt(🔍 Search Env > )+change-header(  type to filter │ esc: normal mode │ enter: copy value)+rebind(esc)"
      "--bind=esc:disable-search+rebind(j,k,q,g,G,y,n,e,i,/)+change-prompt(🌎 Environment > )+change-header($hdr)+unbind(esc)"
    )
  else
    fzf_mode_flags=(
      "--query=$query"
    )
  fi

  local preview_cmd='
    k=$(echo {1} | sed "s/\x1b\[[0-9;]*m//g" | tr -d " ")
    v=$(printenv "$k" 2>/dev/null)
    printf "\033[1;38;2;203;166;247m%s\033[0m \033[2m(%d chars)\033[0m\n" "$k" "${#v}"
    printf "\033[38;2;108;112;134m────────────────────────────────────────────────────────\033[0m\n"
    if [[ "$k" == *PATH* ]] || [[ "$v" == /*:* ]]; then
      echo "$v" | tr ":" "\n" | awk "{
        cmd = \"test -e \\\"\" \$0 \"\\\"\"
        if (system(cmd) == 0) {
          printf \"%2d. \033[32m✔\033[0m %s\n\", NR, \$0
        } else {
          printf \"%2d. \033[31m✖\033[0m \033[2m%s (missing)\033[0m\n\", NR, \$0
        }
      }"
    else
      printf "%s\n" "$v"
    fi
  '

  local selection
  selection=$(_list_env_vars | fzf \
    --ansi \
    --delimiter='\t' \
    --height=~55% \
    --layout=reverse \
    --border=rounded \
    --pointer="❯ " \
    --prompt="🌎 Environment > " \
    --header="$hdr" \
    --color="header:italic:dim,prompt:bold:blue,pointer:bold:magenta" \
    "${fzf_mode_flags[@]}" \
    --preview="$preview_cmd" \
    --preview-window='right:55%:wrap' \
    --expect="y,n,e")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_line
  selected_line=$(echo "$selection" | sed '1d')
  [ -z "$selected_line" ] && return 0

  local var_name
  var_name=$(printf "%s" "$selected_line" | awk -F'\t' '{print $1}' | sed $'s/\x1b\\[[0-9;]*m//g' | tr -d ' ')
  [ -z "$var_name" ] && return 0
  local var_val="${(P)var_name}"

  case "$key" in
    e)
      print -z "export ${var_name}=${(qq)var_val}"
      ;;
    n)
      if (( $+functions[copy] )); then
        printf "%s=%s" "$var_name" "$var_val" | copy
        printf "\033[32m✔ Copied %s=<value> to clipboard\033[0m\n" "$var_name"
      else
        printf "%s=%s\n" "$var_name" "$var_val"
      fi
      ;;
    *)
      if (( $+functions[copy] )); then
        printf "%s" "$var_val" | copy
        printf "\033[32m✔ Copied value of %s to clipboard\033[0m\n" "$var_name"
      else
        printf "%s\n" "$var_val"
      fi
      ;;
  esac
}

# Interactive Cheat-Sheet Browser (cheath)
# Powered by tlrc (tldr) + modal-Vim FZF with live example previews
cheath() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mcheath\033[0m — Interactive modal-Vim CLI cheat-sheet browser (tldr)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  cheath             Browse all command cheat sheets in FZF\n"
    printf "  cheath <query>     Open pre-filtered by <query> (e.g. cheath tar)\n"
    printf "  Enter              Print full cheat sheet to terminal\n"
    printf "  e                  Insert command name onto Zsh prompt\n"
    return 0
  fi

  if ! command -v tldr &>/dev/null; then
    printf "\033[31m✖ 'tldr' (tlrc) is not installed.\033[0m\n" >&2
    return 1
  fi

  local pages
  pages="$(tldr --list 2>/dev/null)"
  if [ -z "$pages" ]; then
    tldr --update >/dev/null 2>&1 || true
    pages="$(tldr --list 2>/dev/null)"
  fi

  if [ -z "$pages" ]; then
    printf "\033[33mNo tldr pages available. Run 'tldr --update' to fetch pages.\033[0m\n" >&2
    return 1
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    if [ $# -gt 0 ]; then
      tldr "$@"
    else
      printf "%s\n" "$pages"
    fi
    return $?
  fi

  local query="$*"
  local hdr="  j/k: navigate │ /: search │ enter: print cheat sheet │ e: insert cmd │ q: quit"
  local fzf_mode_flags=()
  if [ -z "$query" ]; then
    fzf_mode_flags=(
      "--disabled"
      "--bind=start:unbind(esc)"
      "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort"
      "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,e,i,/)+change-prompt(🔍 Search Cheat Sheets > )+change-header(  type to filter │ esc: normal mode │ enter: view)+rebind(esc)"
      "--bind=i:enable-search+unbind(j,k,q,g,G,e,i,/)+change-prompt(🔍 Search Cheat Sheets > )+change-header(  type to filter │ esc: normal mode │ enter: view)+rebind(esc)"
      "--bind=esc:disable-search+rebind(j,k,q,g,G,e,i,/)+change-prompt(📚 Cheat Sheets > )+change-header($hdr)+unbind(esc)"
    )
  else
    fzf_mode_flags=(
      "--query=$query"
    )
  fi

  local selection
  selection=$(printf "%s\n" "$pages" | fzf \
    --height=~60% \
    --layout=reverse \
    --border=rounded \
    --pointer="❯ " \
    --prompt="📚 Cheat Sheets > " \
    --header="$hdr" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:cyan" \
    "${fzf_mode_flags[@]}" \
    --bind="ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up" \
    --preview='tldr --color always {} 2>/dev/null' \
    --preview-window='right:65%:wrap' \
    --expect="e")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local cmd_name
  cmd_name=$(echo "$selection" | sed '1d' | head -n1)
  [ -z "$cmd_name" ] && return 0

  if [ "$key" = "e" ]; then
    print -z "$cmd_name "
  else
    tldr --color always "$cmd_name"
  fi
}
