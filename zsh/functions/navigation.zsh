# Directory Navigation Functions

take() {
  if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "Usage: take <dir/|file|path/to/name>\n"
    printf "  take path/to/dir/      → Create directory and cd into it\n"
    printf "  take path/to/file.ext  → Create parent directory, cd into it, and touch file\n"
    printf "  take my-project        → Create directory and cd into it\n"
    return 0
  fi

  local target="$1"
  local base="${target:t}"

  # 1. Existing file or directory
  if [ -d "$target" ]; then
    cd "$target"
    return 0
  elif [ -f "$target" ]; then
    cd "${target:h}" && return 0
  fi

  # 2. Trailing slash, or extensionless name -> Directory mode
  if [[ "$target" == */ || ( "$base" != *.* && "$base" != Dockerfile && "$base" != Makefile && "$base" != Procfile ) || "$base" == .* ]]; then
    mkdir -p "$target" && cd "$target"
  else
    # 3. File with extension -> Create parent dir, cd, and touch file
    local parent_dir="${target:h}"
    if [ "$parent_dir" = "$target" ] || [ -z "$parent_dir" ] || [ "$parent_dir" = "." ]; then
      touch "$base"
    else
      mkdir -p "$parent_dir" && cd "$parent_dir" && touch "$base"
    fi
  fi
}

groot() {
  _require_git_repo || return 1
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  cd "$root"
}

# Jump from any worktree or subdirectory to the primary repository root
gmain() {
  _require_git_repo || return 1
  local main_root
  main_root="$(_git_main_root)"
  [ -n "$main_root" ] && cd "$main_root"
}

# Smart Ancestor Navigation: 'up' (1 level), 'up 3' (N levels), 'up 3549' or 'up sales' (ancestor name/substring)
up() {
  local target="${1:-1}"
  local curr="$PWD"

  if [[ "$target" == "-h" || "$target" == "--help" ]]; then
    printf "Usage: up [N | <ancestor-name-or-substring>]\n"
    printf "  up        → Go up 1 directory\n"
    printf "  up 3      → Go up 3 directories\n"
    printf "  up sales  → Jump up to ancestor directory matching 'sales'\n"
    return 0
  fi

  # 1. Pure numeric level navigation for small numbers (1..10)
  if [[ "$target" =~ ^[0-9]+$ ]] && (( target >= 1 && target <= 10 )); then
    # Check if there is an exact directory name matching this number first (e.g. directory named "2")
    local p="$curr"
    p="$(dirname "$p")"
    while [ "$p" != "/" ] && [ -n "$p" ]; do
      if [[ "${(L)$(basename "$p")}" == "${(L)target}" ]]; then
        cd "$p" || return 1
        return 0
      fi
      p="$(dirname "$p")"
    done

    # Ascend N levels
    local target_path=""
    local i
    for ((i = 0; i < target; i++)); do
      target_path="../$target_path"
    done
    cd "$target_path" || return 1
    return 0
  fi

  # 2. Search upward: Pass 1 - Exact match (case-insensitive)
  local base_name=""
  local p="$curr"
  p="$(dirname "$p")"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    base_name="$(basename "$p")"
    if [[ "${(L)base_name}" == "${(L)target}" ]]; then
      cd "$p" || return 1
      return 0
    fi
    p="$(dirname "$p")"
  done

  # Pass 2 - Substring / Prefix match (case-insensitive)
  p="$curr"
  p="$(dirname "$p")"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    base_name="$(basename "$p")"
    if [[ "${(L)base_name}" == *"${(L)target}"* ]]; then
      cd "$p" || return 1
      return 0
    fi
    p="$(dirname "$p")"
  done

  # 3. Safety fallback: If target was not found as an ancestor, stay put and warn
  printf "\033[31m✖ No ancestor directory matching '%s' found.\033[0m\n" "$target" >&2
  return 1
}

# Tab completion for up: dynamically lists ancestor directory names
_up() {
  local -a ancestors
  local p="$PWD"
  p="$(dirname "$p")"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    ancestors+=("$(basename "$p")")
    p="$(dirname "$p")"
  done
  _describe 'ancestor directory' ancestors
}
(( $+functions[compdef] )) && compdef _up up

# Smart Directory Tree: 'tree' (full), 'tree 3' (3 levels), 'tree 2 src/' or 'tree src/ 2', 'tree -L 3'
unalias tree lt 2>/dev/null || true

tree() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "Usage: tree [N] [path] [flags...]\n"
    printf "  tree          -> Full recursive directory tree\n"
    printf "  tree 3        -> Tree limited to 3 levels deep\n"
    printf "  tree 2 src/   -> Tree of src/ limited to 2 levels deep\n"
    printf "  tree -L 3     -> Standard -L / --level flag also supported\n"
    return 0
  fi

  local level=""
  if [[ "$1" =~ ^[0-9]+$ ]] && [ ! -e "$1" ]; then
    level="$1"
    shift
  elif (( $# >= 2 )) && [[ "$2" =~ ^[0-9]+$ ]] && [ ! -e "$2" ] && [[ "$1" != "-L" && "$1" != "--level" ]]; then
    level="$2"
    set -- "$1" "${@:3}"
  fi

  if command -v eza &>/dev/null; then
    if [ -n "$level" ]; then
      eza --tree --icons --level="$level" "$@"
    else
      eza --tree --icons "$@"
    fi
  elif command -v tree &>/dev/null; then
    if [ -n "$level" ]; then
      command tree -C -L "$level" "$@"
    else
      command tree -C "$@"
    fi
  else
    if [ -n "$level" ]; then
      find "${1:-.}" -maxdepth "$level" 2>/dev/null
    else
      find "${1:-.}" 2>/dev/null
    fi
  fi
}

# Level-2 Default Tree: 'lt' (2 levels), 'lt 3' (3 levels), 'lt src/' (2 levels in src/)
lt() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "Usage: lt [N] [path] [flags...]\n"
    printf "  lt            -> Tree limited to 2 levels deep (default)\n"
    printf "  lt 3          -> Tree limited to 3 levels deep\n"
    printf "  lt src/       -> Tree of src/ limited to 2 levels deep\n"
    return 0
  fi

  local has_level=false
  if [[ "$1" =~ ^[0-9]+$ ]] && [ ! -e "$1" ]; then
    has_level=true
  elif (( $# >= 2 )) && [[ "$2" =~ ^[0-9]+$ ]] && [ ! -e "$2" ] && [[ "$1" != "-L" && "$1" != "--level" ]]; then
    has_level=true
  else
    local arg
    for arg in "$@"; do
      if [[ "$arg" == -L* || "$arg" == --level* ]]; then
        has_level=true
        break
      fi
    done
  fi

  if [ "$has_level" = true ]; then
    tree "$@"
  else
    tree 2 "$@"
  fi
}

# Interactive Session Directory Stack Jumper (d)
# Uses Zsh auto_pushd history (dirs -v) with modal-Vim FZF & eza tree preview
d() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "Usage: d [index | query]\n"
    printf "  d          → Browse session directory stack in modal-Vim FZF\n"
    printf "  d 2        → Jump directly to directory stack entry #2\n"
    printf "  d <query>  → Filter directory stack by query\n"
    return 0
  fi

  if [[ "$1" =~ ^[0-9]+$ ]]; then
    local target_dir
    target_dir=$(dirs -l -p | sed -n "$(( $1 + 1 ))p")
    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
      cd "$target_dir"
      return 0
    fi
    printf "\033[31m✖ Directory stack index %s out of range.\033[0m\n" "$1" >&2
    return 1
  fi

  local stack
  stack=$(dirs -v | awk '!seen[$2]++')
  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "%s\n" "$stack"
    return 0
  fi

  local -a fzf_mode_flags
  _fzf_vim_mode "📂 Directory Stack > " "  j/k: navigate │ /: search │ enter: cd │ e: edit in editor │ y: copy path │ q: quit" "cd" "e,y" "$*"

  local selected
  selected=$(printf "%s\n" "$stack" | fzf \
    --delimiter=$'\t' \
    --height=~40% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    --preview='p={2}; p="${p/#\~/$HOME}"; if command -v eza &>/dev/null; then eza --tree --level=2 --icons --color=always "$p" 2>/dev/null; else ls -la "$p" 2>/dev/null; fi' \
    --preview-window='right:55%:wrap')

  [ -z "$selected" ] && return 0

  local key
  key=$(echo "$selected" | head -n1)
  local chosen_line
  chosen_line=$(echo "$selected" | sed '1d')
  local chosen
  chosen=$(echo "$chosen_line" | awk '{print $2}')
  chosen="${chosen/#\~/$HOME}"

  [ -z "$chosen" ] && return 0

  case "$key" in
    e)
      "${EDITOR:-nvim}" "$chosen"
      ;;
    y)
      _copy_or_print "$chosen" "directory path: $chosen"
      ;;
    *)
      [ -d "$chosen" ] && cd "$chosen"
      ;;
  esac
}

