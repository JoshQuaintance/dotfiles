# Interactive shell functions
# Functions in this file execute in the parent shell environment (allowing cd, export, source)

# 1. Directory Navigation
take() {
  mkdir -p "$1" && cd "$1"
}

groot() {
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

# 2. Configuration Manager (auto-reloads shell rc if modified)
conf() {
  local target="${1:-shell}"
  local target_file=""
  local is_shell_rc=false

  case "$target" in
    shell|"")
      target_file="$HOME/.zshrc"
      is_shell_rc=true
      ;;
    zsh)
      target_file="$HOME/.zshrc"
      is_shell_rc=true
      ;;
    bash)
      target_file="$HOME/.bashrc"
      is_shell_rc=true
      ;;
    alias|aliases)
      target_file="$HOME/.aliases"
      is_shell_rc=true
      ;;
    func|functions)
      target_file="${DOTFILES_DIR:-$HOME/.dotfiles}/zsh/functions.zsh"
      is_shell_rc=true
      ;;
    nvim|vim)
      target_file="$HOME/.config/nvim"
      ;;
    dotfiles|dots)
      target_file="${DOTFILES_DIR:-$HOME/.dotfiles}"
      [ ! -d "$target_file" ] && [ -d "$HOME/Codes/dotfiles" ] && target_file="$HOME/Codes/dotfiles"
      ;;
    git)
      target_file="$HOME/.gitconfig"
      ;;
    starship)
      target_file="$HOME/.config/starship.toml"
      ;;
    ghostty)
      target_file="$HOME/.config/ghostty/config"
      ;;
    bat)
      target_file="$HOME/.config/bat/config"
      ;;
    eza)
      target_file="$HOME/.config/eza/theme.yml"
      ;;
    zed)
      target_file="$HOME/.config/zed/keymap.json"
      ;;
    *)
      if [ -f "$1" ] || [ -d "$1" ]; then
        target_file="$1"
      else
        echo "Unknown config target: $1"
        echo "Usage: conf [shell|alias|functions|nvim|ghostty|bat|eza|zed|dotfiles|git|starship|<path>]"
        return 1
      fi
      ;;
  esac

  local editor="${EDITOR:-nvim}"
  command -v "$editor" &>/dev/null || editor="nano"

  if [ -d "$target_file" ]; then
    "$editor" "$target_file"
    return 0
  fi

  [ ! -f "$target_file" ] && touch "$target_file"

  local before_sum
  before_sum=$(cksum "$target_file" 2>/dev/null)

  "$editor" "$target_file"

  local after_sum
  after_sum=$(cksum "$target_file" 2>/dev/null)

  if [ "$before_sum" != "$after_sum" ]; then
    if [ "$is_shell_rc" = true ]; then
      echo "Changes detected. Sourcing $target_file..."
      source "$target_file"
      echo "✔ Terminal environment updated!"
    else
      echo "✔ Saved changes to $target_file"
    fi
  else
    echo "No changes made."
  fi
}

# 3. Development & Testing Helpers
clone() {
  local repo=$1
  echo "Cloning $repo - git clone git@github.com:$repo.git"
  git clone "git@github.com:$repo.git"
}

port() {
  lsof -i :"$1"
}

gsearch() {
  git log --all --grep="$1" --oneline
}

# 4. Interactive Package.json Script Selector (FZF)
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

# 5. Dotfiles Auto-Reloading Wrapper
dotupdate() {
  command dotupdate "$@"
  local ret=$?
  if [ $ret -eq 0 ] && [ "$1" != "-c" ] && [ "$1" != "--check" ] && [ -f "$HOME/.zshrc" ]; then
    echo "Reloading ~/.zshrc..."
    source "$HOME/.zshrc"
  fi
  return $ret
}

dotcheck() {
  command dotcheck "$@"
}

# ==========================================
# 6. Automatic Directory Listing on cd (_auto_ls)
# ==========================================

_auto_ls() {
  # 1. Interactive & TTY guard: only run in interactive terminals with attached stdout
  [[ -o interactive ]] || return 0
  [[ -t 1 ]] || return 0

  # 2. Quick toggle guard (1 = enabled, 0 = disabled)
  [[ "${AUTO_LS:-1}" == "1" ]] || return 0

  # 3. File count threshold guard (default 35 items)
  local max="${AUTO_LS_MAX:-35}"
  local -a items=(*(N))
  local count="${#items}"

  if (( count == 0 )); then
    return 0
  elif (( count > max )); then
    print "\033[38;2;147;153;178m󰉋 $count items (threshold $max) — run \033[1;38;2;203;166;247m'l'\033[0;38;2;147;153;178m or \033[1;38;2;203;166;247m'll'\033[0;38;2;147;153;178m to view\033[0m"
  else
    if command -v eza &>/dev/null; then
      eza --icons --group-directories-first
    else
      ls -C
    fi
  fi
}

# Register the chpwd hook safely via add-zsh-hook
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _auto_ls

# Toggle function with support for on/off/status/custom threshold
toggle-autols() {
  case "$1" in
    on|enable|1)
      export AUTO_LS=1
      print "\033[38;2;166;227;161m✔ Auto-ls enabled\033[0m (threshold: ${AUTO_LS_MAX:-35} items)"
      _auto_ls
      ;;
    off|disable|0)
      export AUTO_LS=0
      print "\033[38;2;243;139;168m󰅙 Auto-ls disabled\033[0m"
      ;;
    status)
      if [[ "${AUTO_LS:-1}" == "1" ]]; then
        print "\033[38;2;166;227;161m✔ Auto-ls is enabled\033[0m (threshold: ${AUTO_LS_MAX:-35} items)"
      else
        print "\033[38;2;243;139;168m󰅙 Auto-ls is disabled\033[0m"
      fi
      ;;
    <->)
      export AUTO_LS_MAX="$1"
      export AUTO_LS=1
      print "\033[38;2;166;227;161m✔ Auto-ls threshold set to $1 items\033[0m"
      _auto_ls
      ;;
    *)
      if [[ "${AUTO_LS:-1}" == "1" ]]; then
        export AUTO_LS=0
        print "\033[38;2;243;139;168m󰅙 Auto-ls disabled\033[0m (toggle back with 'als')"
      else
        export AUTO_LS=1
        print "\033[38;2;166;227;161m✔ Auto-ls enabled\033[0m (threshold: ${AUTO_LS_MAX:-35} items)"
        _auto_ls
      fi
      ;;
  esac
}

# ==========================================
# 7. Search Aliases & Functions (fa / aliases)
# ==========================================

fa() {
  local dot_dir="${DOTFILES_DIR:-$HOME/Codes/dotfiles}"
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
    for fn in take groot conf clone port gsearch npmr bunr pnpmr dotupdate dotcheck toggle-autols acceptance fa; do
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
    # Interactive FZF browser: searches ONLY command name (--nth=2) by default
    local selected
    selected=$(_gen_list | fzf \
      --delimiter='\t' \
      --nth=2 \
      --with-nth=1,2,3 \
      --query="$query" \
      --bind='ctrl-j:down,ctrl-k:up,alt-j:down,alt-k:up,ctrl-d:preview-down,ctrl-u:preview-up,shift-down:preview-down,shift-up:preview-up,ctrl-s:change-nth(2|2,3)' \
      --preview='which {2} 2>/dev/null | if command -v bat &>/dev/null; then bat -l zsh --color=always --style=plain; else cat; fi' \
      --preview-window='right:55%:wrap' \
      --header='Ctrl-j/k to navigate • Ctrl-s toggle search target (name vs all) • Enter to paste • Esc to quit' \
      --prompt='🔍 Search Aliases & Functions > ')

    if [ -n "$selected" ]; then
      local cmd
      cmd=$(echo "$selected" | awk -F'\t' '{print $2}' | xargs)
      print -z "$cmd "
    fi
  else
    _gen_list | awk -F'\t' -v q="$query" 'tolower($2) ~ tolower(q)'
  fi
}
