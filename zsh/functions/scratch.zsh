# Instant Terminal Scratchpad (scratch)
# Usage:
#   scratch               # Open today's scratchpad (~/.scratch/YYYY-MM-DD.md)
#   scratch notes         # Open a named scratchpad (~/.scratch/notes.md)
#   scratch -l / --list   # Browse previous scratchpads with interactive fzf + preview
#   scratch -d / --dir    # Output or cd to scratch directory
#   curl ... | scratch    # Pipe stdin directly into a new timestamped scratchpad

scratch() {
  local scratch_dir="${SCRATCH_DIR:-$HOME/.scratch}"
  mkdir -p "$scratch_dir"

  # Browse / list mode
  if [ "$1" = "-l" ] || [ "$1" = "--list" ]; then
    if ! ls -1 "$scratch_dir"/*.md &>/dev/null; then
      printf "\033[33mNo scratchpads found in %s\033[0m\n" "$scratch_dir"
      return 0
    fi

    if command -v fzf &>/dev/null; then
      local selected
      selected=$(find "$scratch_dir" -maxdepth 1 -name "*.md" -type f -exec basename {} \; | sort -r | fzf \
        --height=~50% \
        --layout=reverse \
        --border=rounded \
        --prompt="📝 Select Scratchpad > " \
        --header="Enter: open in editor • Esc: cancel" \
        --preview="if command -v bat &>/dev/null; then bat --style=plain --color=always '$scratch_dir/{}'; else cat '$scratch_dir/{}'; fi" \
        --preview-window='right:60%:wrap')

      if [ -n "$selected" ]; then
        local editor="${EDITOR:-nvim}"
        command -v "$editor" &>/dev/null || editor="nano"
        "$editor" "$scratch_dir/$selected"
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
