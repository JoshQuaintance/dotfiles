# Interactive Package.json Script Selector (FZF)

_find_package_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/package.json" ]; then
      echo "$dir/package.json"
      return 0
    fi
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_extract_pkg_scripts() {
  local pkg_file="$1"
  if command -v jq &>/dev/null; then
    jq -r 'if .scripts then .scripts | to_entries[] | "\(.key)\t\(.value)" else empty end' "$pkg_file" 2>/dev/null
  elif command -v node &>/dev/null; then
    node -e '
      try {
        const fs = require("fs");
        const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        if (pkg.scripts) {
          for (const [k, v] of Object.entries(pkg.scripts)) {
            console.log(k + "\t" + v);
          }
        }
      } catch (e) {}
    ' "$pkg_file" 2>/dev/null
  elif command -v bun &>/dev/null; then
    bun -e '
      try {
        const fs = require("fs");
        const pkg = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
        if (pkg.scripts) {
          for (const [k, v] of Object.entries(pkg.scripts)) {
            console.log(k + "\t" + v);
          }
        }
      } catch (e) {}
    ' "$pkg_file" 2>/dev/null
  fi
}

_pkg_script_select() {
  local runner="${1:-npm}"
  local pkg_file
  pkg_file=$(_find_package_json)

  if [ -z "$pkg_file" ] || [ ! -f "$pkg_file" ]; then
    command "$runner" run
    return $?
  fi

  local raw_scripts
  raw_scripts=$(_extract_pkg_scripts "$pkg_file")

  if [ -z "$raw_scripts" ]; then
    printf "\033[33mNo scripts found in %s\033[0m\n" "$pkg_file" >&2
    return 1
  fi

  if ! command -v fzf &>/dev/null; then
    printf "\033[33mfzf not found. Falling back to %s run...\033[0m\n" "$runner" >&2
    command "$runner" run
    return $?
  fi

  local max_len
  max_len=$(echo "$raw_scripts" | awk -F'\t' 'BEGIN { max=0 } { if (length($1) > max) max=length($1) } END { if (max < 16) max=16; if (max > 32) max=32; print max }')

  local formatted
  formatted=$(echo "$raw_scripts" | awk -F'\t' -v len="$max_len" '{ printf "\033[1;36m%-" len "s\033[0m \033[90m│\033[0m %s\t%s\n", $1, $2, $1 }')

  local selection
  selection=$(echo "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1 \
    --disabled \
    --height=~50% \
    --min-height=10 \
    --layout=reverse \
    --border=rounded \
    --info=inline \
    --pointer="▶" \
    --prompt="⚡ $runner run > " \
    --header="  j/k: navigate │ /: search │ enter: run │ q: quit" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,ctrl-j:down,ctrl-k:up,ctrl-n:down,ctrl-p:up,down:down,up:up,enter:accept" \
    --bind="/:enable-search+unbind(j,k,q,g,G)+change-prompt(🔍 filter > )+change-header(  type to filter │ esc: normal mode │ enter: run)" \
    --bind="esc:disable-search+clear-query+rebind(j,k,q,g,G)+change-prompt(⚡ $runner run > )+change-header(  j/k: navigate │ /: search │ enter: run │ q: quit)")

  local selected
  selected=$(echo "$selection" | awk -F'\t' '{print $2}')

  if [ -n "$selected" ]; then
    printf "\033[1;32m➜\033[0m \033[1;36m%s run %s\033[0m\n" "$runner" "$selected"
    command "$runner" run "$selected"
  fi
}

# npm / bun / pnpm wrappers (intercept 'run' without arguments)
npm() {
  if [ "$1" = "run" ] && [ "$#" -eq 1 ]; then
    _pkg_script_select npm
  else
    command npm "$@"
  fi
}

bun() {
  if [ "$1" = "run" ] && [ "$#" -eq 1 ]; then
    _pkg_script_select bun
  else
    command bun "$@"
  fi
}

pnpm() {
  if [ "$1" = "run" ] && [ "$#" -eq 1 ]; then
    _pkg_script_select pnpm
  else
    command pnpm "$@"
  fi
}

# Direct shortcuts: npmr, bunr, pnpmr
npmr() {
  if [ "$#" -eq 0 ]; then
    _pkg_script_select npm
  else
    command npm run "$@"
  fi
}

bunr() {
  if [ "$#" -eq 0 ]; then
    _pkg_script_select bun
  else
    command bun run "$@"
  fi
}

pnpmr() {
  if [ "$#" -eq 0 ]; then
    _pkg_script_select pnpm
  else
    command pnpm run "$@"
  fi
}
