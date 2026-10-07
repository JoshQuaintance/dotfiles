# Instant Terminal Scratchpad (scratch)
# Usage:
#   scratch               # Open today's scratchpad (~/.scratch/YYYY-MM-DD.md)
#   scratch notes         # Open a named scratchpad (~/.scratch/notes.md)
#   scratch -l / --list   # Browse/delete scratchpads with interactive fzf + preview (space+x: delete)
#   scratch -g [query]    # Search inside all scratchpads with rg/grep + fzf preview
#   scratch -d / --dir    # Jump to scratch directory
#   curl ... | scratch    # Pipe stdin directly into a scratchpad

scratch() {
  local scratch_dir="${SCRATCH_DIR:-$HOME/.scratch}"
  mkdir -p "$scratch_dir"

  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mscratch\033[0m — Instant markdown scratchpad manager\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  scratch              Open today's scratchpad (~/.scratch/YYYY-MM-DD.md)\n"
    printf "  scratch <name>       Open named scratchpad (~/.scratch/<name>.md)\n"
    printf "  scratch -l           Browse scratchpads in FZF (enter: open, space+x: delete)\n"
    printf "  scratch -g [query]   Search contents across all scratchpads\n"
    printf "  scratch -d           cd into %s\n" "$scratch_dir"
    return 0
  fi

  # Content grep / search mode
  if [ "$1" = "-g" ] || [ "$1" = "--grep" ] || [ "$1" = "-s" ] || [ "$1" = "--search" ]; then
    shift
    local query="$*"
    local md_files=("$scratch_dir"/*.md(N))
    if [ "${#md_files[@]}" -eq 0 ]; then
      printf "\033[33mNo scratchpads found in %s\033[0m\n" "$scratch_dir"
      return 0
    fi

    local hits
    if command -v rg &>/dev/null; then
      hits=$(cd "$scratch_dir" && rg --line-number --no-heading --color=always "${query:-.}" ./*.md 2>/dev/null | sed 's|^\./||')
    else
      hits=$(cd "$scratch_dir" && grep -rnH --color=always "${query:-.}" ./*.md 2>/dev/null | sed 's|^\./||')
    fi

    if [ -z "$hits" ]; then
      printf "\033[33mNo matches found in %s\033[0m\n" "$scratch_dir"
      return 0
    fi

    if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
      printf "%s\n" "$hits"
      return 0
    fi

    local match
    match=$(printf "%s\n" "$hits" | fzf \
      --ansi \
      --delimiter=':' \
      --height=~55% \
      --layout=reverse \
      --border=rounded \
      --disabled \
      --pointer="❯ " \
      --prompt="🔍 Scratch Search > " \
      --header="  j/k: navigate │ /: filter │ enter: open at line │ q: quit" \
      --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
      --bind="start:unbind(esc)" \
      --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept" \
      --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Filter > )+change-header(  type to filter │ esc: normal mode │ enter: open)+rebind(esc)" \
      --bind="i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Filter > )+change-header(  type to filter │ esc: normal mode │ enter: open)+rebind(esc)" \
      --bind="esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(🔍 Scratch Search > )+change-header(  j/k: navigate │ /: filter │ enter: open at line │ q: quit)+unbind(esc)" \
      --preview="f={1}; ln={2}; if command -v bat &>/dev/null; then s=\$(( ln > 10 ? ln - 10 : 1 )); e=\$(( ln + 25 )); bat --style=numbers --color=always --highlight-line \"\$ln\" --line-range \"\$s:\$e\" '$scratch_dir/'\"\$f\" 2>/dev/null; else cat '$scratch_dir/'\"\$f\"; fi" \
      --preview-window='right:60%:wrap')

    if [ -n "$match" ]; then
      local clean_match file_part line_part
      clean_match=$(printf "%s" "$match" | sed $'s/\x1b\\[[0-9;]*m//g')
      file_part=$(printf "%s" "$clean_match" | cut -d: -f1)
      line_part=$(printf "%s" "$clean_match" | cut -d: -f2)
      local editor="${EDITOR:-nvim}"
      command -v "$editor" &>/dev/null || editor="nano"
      if [ -n "$line_part" ] && [[ "$editor" == *vim* ]]; then
        "$editor" "+$line_part" "$scratch_dir/$file_part"
      else
        "$editor" "$scratch_dir/$file_part"
      fi
    fi
    return 0
  fi

  # Browse / list mode
  if [ "$1" = "-l" ] || [ "$1" = "--list" ]; then
    local md_files=("$scratch_dir"/*.md(N))
    if [ "${#md_files[@]}" -eq 0 ]; then
      printf "\033[33mNo scratchpads found in %s\033[0m\n" "$scratch_dir"
      return 0
    fi

    if command -v fzf &>/dev/null && [ -t 1 ]; then
      local selection
      selection=$(find "$scratch_dir" -maxdepth 1 -name "*.md" -type f -exec basename {} \; | sort -r | fzf \
        --multi \
        --height=~50% \
        --layout=reverse \
        --border=rounded \
        --disabled \
        --pointer="❯ " \
        --marker="✓ " \
        --prompt="📝 Scratchpad > " \
        --header="  j/k: navigate │ space: select │ /: search │ enter: open │ x: delete │ q: quit" \
        --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green,marker:bold:red" \
        --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,space:toggle+down,enter:accept" \
        --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,space,x,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: open)+rebind(esc)" \
        --bind="i:enable-search+unbind(j,k,q,g,G,space,x,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: open)+rebind(esc)" \
        --bind="esc:disable-search+rebind(j,k,q,g,G,space,x,i,/)+change-prompt(📝 Scratchpad > )+change-header(  j/k: navigate │ space: select │ /: search │ enter: open │ x: delete │ q: quit)+unbind(esc)" \
        --bind="start:unbind(esc)" \
        --preview="if command -v bat &>/dev/null; then bat --style=plain --color=always '$scratch_dir/{}'; else cat '$scratch_dir/{}'; fi" \
        --preview-window='right:60%:wrap' \
        --expect="x")

      [ -z "$selection" ] && return 0

      local key
      key=$(echo "$selection" | head -n1)
      local selected_lines
      selected_lines=$(echo "$selection" | sed '1d')
      [ -z "$selected_lines" ] && return 0

      local -a targets full_paths
      while IFS= read -r item; do
        if [ -n "$item" ]; then
          targets+=("$item")
          full_paths+=("$scratch_dir/$item")
        fi
      done <<< "$selected_lines"

      [ "${#targets[@]}" -eq 0 ] && return 0

      if [ "$key" = "x" ]; then
        printf "\033[1;31m⚠ Delete %d scratchpad(s) (%s)? [y/N]: \033[0m" "${#targets[@]}" "${(j:, :)targets}"
        local confirm=""
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          rm -f -- "${full_paths[@]}"
          printf "\033[32m✔ Deleted %d scratchpad(s).\033[0m\n" "${#targets[@]}"
        else
          printf "\033[2mCancelled.\033[0m\n"
        fi
      else
        local editor="${EDITOR:-nvim}"
        command -v "$editor" &>/dev/null || editor="nano"
        "$editor" "${full_paths[@]}"
      fi
      return 0
    else
      ls -lh "$scratch_dir"
      return 0
    fi
  fi

  # Directory jump mode
  if [ "$1" = "-d" ] || [ "$1" = "--dir" ]; then
    cd "$scratch_dir" || return 1
    return 0
  fi

  # Determine target file
  local target_file=""
  if [ -n "$1" ]; then
    local name="$1"
    [[ "$name" != *.md ]] && name="${name}.md"
    target_file="$scratch_dir/$name"
  else
    target_file="$scratch_dir/$(date +%Y-%m-%d).md"
  fi

  # Handle piped stdin (e.g. echo "data" | scratch or curl ... | scratch test)
  if [ ! -t 0 ]; then
    cat >> "$target_file"
    printf "\033[32m✔ Appended stdin to %s\033[0m\n" "$target_file"
    return 0
  fi

  # Add header if file is newly created
  if [ ! -f "$target_file" ]; then
    printf "# Scratchpad: %s\nCreated: %s\n\n" "$(basename "$target_file" .md)" "$(date '+%Y-%m-%d %H:%M:%S')" > "$target_file"
  fi

  local editor="${EDITOR:-nvim}"
  command -v "$editor" &>/dev/null || editor="nano"
  "$editor" "$target_file"
}
