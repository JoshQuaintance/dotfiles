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
    for fn in take up groot gmain conf dotbranch clone port gsearch wt gwtnew gwts gwtdel gwtclean gbclean y copy paste scratch extract npmr bunr pnpmr toggle-autols fa notify gl gco sdiff; do
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
