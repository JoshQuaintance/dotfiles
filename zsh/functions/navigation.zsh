# Directory Navigation Functions

take() {
  mkdir -p "$1" && cd "$1"
}

groot() {
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# Smart Ancestor Navigation: 'up 3' or 'up src' or 'up' (defaults to 1 level up)
up() {
  local target="${1:-1}"

  # If numeric, go up N levels
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    local path=""
    for ((i = 0; i < target; i++)); do
      path="../$path"
    done
    cd "$path" || return 1
    return 0
  fi

  # If string, search upward for matching ancestor directory name
  local curr="$PWD"
  while [ "$curr" != "/" ] && [ -n "$curr" ]; do
    if [ "$(basename "$curr")" = "$target" ]; then
      cd "$curr" || return 1
      return 0
    fi
    curr="$(dirname "$curr")"
  done

  printf "\033[31m✖ No ancestor directory named '%s' found.\033[0m\n" "$target" >&2
  return 1
}
