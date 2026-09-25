# Directory Navigation Functions

take() {
  mkdir -p "$1" && cd "$1"
}

groot() {
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# Jump from any worktree or subdirectory to the primary repository root
gmain() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local common_dir
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -z "$common_dir" ]; then
    cd "$(git rev-parse --show-toplevel)" || return 1
    return 0
  fi

  local main_root
  main_root="$(cd "$common_dir/.." && pwd)"
  cd "$main_root" || return 1
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

