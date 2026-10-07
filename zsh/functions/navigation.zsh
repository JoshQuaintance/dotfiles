# Directory Navigation Functions

take() {
  mkdir -p "$1" && cd "$1"
}

groot() {
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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
  local p="$curr"
  p="$(dirname "$p")"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    local base_name="$(basename "$p")"
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
    local base_name="$(basename "$p")"
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
