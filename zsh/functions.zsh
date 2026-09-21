# Interactive shell functions
# Functions in this file execute in the parent shell environment (allowing cd, export, source)

# 1. Directory Navigation
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

# 2. Dynamic Configuration Manager (fuzzy matching & auto-reloading)
# Usage:
#   conf                  # Open ~/.zshrc (default)
#   conf <target>         # Smart fuzzy lookup (e.g. conf ghost, conf nvim, conf brew, conf star)
#   conf <path>           # Direct file or directory path
_conf_candidates() {
  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}"

  # 1. Base shell & dotfile anchors
  [ -f "$HOME/.zshrc" ] && printf "zsh\t%s\n" "$HOME/.zshrc"
  [ -f "$HOME/.zshrc" ] && printf "shell\t%s\n" "$HOME/.zshrc"
  [ -f "$HOME/.aliases" ] && printf "alias\t%s\n" "$HOME/.aliases"
  [ -f "$HOME/.aliases" ] && printf "aliases\t%s\n" "$HOME/.aliases"
  [ -f "$dot_dir/zsh/functions.zsh" ] && printf "functions\t%s\n" "$dot_dir/zsh/functions.zsh"
  [ -f "$dot_dir/zsh/functions.zsh" ] && printf "func\t%s\n" "$dot_dir/zsh/functions.zsh"
  [ -f "$HOME/.gitconfig" ] && printf "git\t%s\n" "$HOME/.gitconfig"
  [ -f "$HOME/.gitconfig" ] && printf "gitconfig\t%s\n" "$HOME/.gitconfig"
  [ -f "$dot_dir/Brewfile" ] && printf "brew\t%s\n" "$dot_dir/Brewfile"
  [ -f "$dot_dir/Brewfile" ] && printf "brewfile\t%s\n" "$dot_dir/Brewfile"
  [ -d "$dot_dir" ] && printf "dotfiles\t%s\n" "$dot_dir"
  [ -d "$dot_dir" ] && printf "dots\t%s\n" "$dot_dir"
  [ -d "${SCRATCH_DIR:-$HOME/.scratch}" ] && printf "scratch\t%s\n" "${SCRATCH_DIR:-$HOME/.scratch}"

  # 2. Dynamic discovery in ~/.config
  if [ -d "$cfg_dir" ]; then
    for item in "$cfg_dir"/*(N); do
      local bname="$(basename "$item")"
      [[ "$bname" == .* ]] && continue

      if [ -d "$item" ]; then
        local primary=""
        for sub in "$item"/config*(N) "$item"/settings.json(N) "$item"/theme.yml(N) "$item"/init.lua(N); do
          if [ -f "$sub" ]; then
            primary="$sub"
            break
          fi
        done
        if [ -n "$primary" ]; then
          printf "%s\t%s\n" "$bname" "$primary"
        else
          printf "%s\t%s\n" "$bname" "$item"
        fi
      elif [ -f "$item" ]; then
        local stripped="${bname%.*}"
        printf "%s\t%s\n" "$stripped" "$item"
      fi
    done
  fi
}

conf() {
  local target_file=""
  local is_shell_rc=false

  # 1. If nothing passed, default to editing ~/.zshrc
  if [ -z "$1" ]; then
    target_file="$HOME/.zshrc"
    is_shell_rc=true
  # 2. If an explicit file or directory path was given
  elif [ -f "$1" ] || [ -d "$1" ]; then
    target_file="$1"
  else
    local query="$1"
    local all_candidates
    all_candidates=$(_conf_candidates)

    # Check for exact key match first (case-insensitive)
    local exact_match
    exact_match=$(echo "$all_candidates" | awk -F'\t' -v q="$query" 'tolower($1) == tolower(q) { print $2; exit }')

    if [ -n "$exact_match" ]; then
      target_file="$exact_match"
    else
      # Fuzzy filter candidate entries
      local matches
      matches=$(echo "$all_candidates" | awk -F'\t' -v q="$query" 'tolower($1) ~ tolower(q) || tolower($2) ~ tolower(q) { print $0 }' | sort -u -k2,2)
      local match_count
      match_count=$(echo "$matches" | grep -c . || true)

      if [ "$match_count" -eq 1 ]; then
        target_file=$(echo "$matches" | awk -F'\t' '{print $2}')
      elif command -v fzf &>/dev/null; then
        local candidate_pool="$matches"
        [ -z "$candidate_pool" ] && candidate_pool=$(echo "$all_candidates" | sort -u -k2,2)

        local selected
        selected=$(echo "$candidate_pool" | awk -F'\t' '{ printf "%-16s │ %s\t%s\n", $1, $2, $2 }' | fzf \
          --delimiter='\t' \
          --with-nth=1 \
          --query="$query" \
          --height=~50% \
          --layout=reverse \
          --border=rounded \
          --prompt="⚙  Edit Config > " \
          --header="Enter: open in editor • Esc: cancel" \
          --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
          --preview='if [ -d {2} ]; then if command -v eza &>/dev/null; then eza -la --color=always {2}; else ls -la {2}; fi; elif [ -f {2} ]; then if command -v bat &>/dev/null; then bat --style=plain --color=always --line-range :60 {2}; else head -n 60 {2}; fi; fi' \
          --preview-window='right:55%:wrap')

        if [ -n "$selected" ]; then
          target_file=$(echo "$selected" | awk -F'\t' '{print $2}')
        else
          return 0
        fi
      else
        if [ "$match_count" -gt 1 ]; then
          printf "\033[33mMultiple matches for '%s':\033[0m\n" "$query"
          echo "$matches" | awk -F'\t' '{printf "%2d) %-14s -> %s\n", NR, $1, $2}'
          printf "Select config number: "
          local choice
          read -r choice
          target_file=$(echo "$matches" | sed -n "${choice}p" | awk -F'\t' '{print $2}')
        else
          printf "\033[31m✖ No configuration found matching '%s'.\033[0m\n" "$query"
          return 1
        fi
      fi
    fi
  fi

  if [ -z "$target_file" ]; then
    return 0
  fi

  # Determine if target is a shell rc file that should trigger auto-reloading
  case "$target_file" in
    *"/.zshrc"|*"/.aliases"|*"/zsh/functions.zsh")
      is_shell_rc=true
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

# Git Worktree Interactive Switcher (wt)
# Dynamically queries git worktrees in the current repo and provides an interactive fzf selector
wt() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local worktrees
  worktrees=$(git worktree list 2>/dev/null)

  if [ -z "$worktrees" ]; then
    printf "\033[33m⚠ No worktrees found.\033[0m\n" >&2
    return 1
  fi

  local query="$1"
  if [ -n "$query" ]; then
    local exact_matches
    exact_matches=$(echo "$worktrees" | awk -v q="$query" 'tolower($0) ~ tolower(q) { print $1 }')
    local match_count
    match_count=$(echo "$exact_matches" | grep -c . || true)
    if [ "$match_count" -eq 1 ] && [ -d "$exact_matches" ]; then
      cd "$exact_matches"
      return 0
    fi
  fi

  if command -v fzf &>/dev/null; then
    local selected
    selected=$(echo "$worktrees" | fzf \
      --height=~40% \
      --layout=reverse \
      --border=rounded \
      --query="$query" \
      --prompt="🌿 Switch Worktree > " \
      --header="Enter: cd to worktree • Esc: cancel" \
      --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
      --preview='git -C {1} status -sb 2>/dev/null' \
      --preview-window='right:50%:wrap')

    if [ -n "$selected" ]; then
      local target_dir
      target_dir=$(echo "$selected" | awk '{print $1}')
      if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        cd "$target_dir"
      fi
    fi
  else
    echo "$worktrees" | awk '{printf "%2d) %s\n", NR, $0}'
    local choice
    printf "Select worktree number: "
    read -r choice
    local target_dir
    target_dir=$(echo "$worktrees" | sed -n "${choice}p" | awk '{print $1}')
    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
      cd "$target_dir"
    fi
  fi
}

# Yazi Shell Wrapper (changes directory on exit)
y() {
  local tmp
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  local cwd
  command yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp" 2>/dev/null)" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# Cross-Platform Clipboard Helpers (macOS, Linux Wayland, Linux X11, WSL)
copy() {
  if command -v pbcopy &>/dev/null; then
    pbcopy "$@"
  elif command -v wl-copy &>/dev/null; then
    wl-copy "$@"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard "$@"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --input "$@"
  elif command -v clip.exe &>/dev/null; then
    clip.exe "$@"
  elif [ -n "$TMUX" ]; then
    tmux load-buffer -
  else
    printf "\033[33mNo clipboard utility found (pbcopy, wl-copy, xclip, clip.exe)\033[0m\n" >&2
    return 1
  fi
}

paste() {
  if command -v pbpaste &>/dev/null; then
    pbpaste "$@"
  elif command -v wl-paste &>/dev/null; then
    wl-paste "$@"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard -o "$@"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --output "$@"
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command Get-Clipboard "$@"
  else
    printf "\033[33mNo clipboard utility found (pbpaste, wl-paste, xclip, powershell.exe)\033[0m\n" >&2
    return 1
  fi
}

# 4. Instant Terminal Scratchpad (scratch)
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

# Universal Archive Extractor (extract / x)
extract() {
  if [ -z "$1" ]; then
    printf "\033[33mUsage: extract <archive_file>\033[0m\n" >&2
    printf "Supports: .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .zip, .rar, .7z, .tar.zst, .zst, .gz, .bz2\n" >&2
    return 1
  fi

  if [ ! -f "$1" ]; then
    printf "\033[31m✖ File not found: %s\033[0m\n" "$1" >&2
    return 1
  fi

  local file="$1"
  case "${file:l}" in
    *.tar.bz2|*.tbz2)   tar xvjf "$file" ;;
    *.tar.gz|*.tgz)     tar xvzf "$file" ;;
    *.tar.xz|*.txz)     tar xvJf "$file" ;;
    *.tar.zst)          tar --zstd -xvf "$file" 2>/dev/null || zstd -d -c "$file" | tar xvf - ;;
    *.tar)              tar xvf "$file" ;;
    *.bz2)              bunzip2 "$file" ;;
    *.rar)              unrar x "$file" ;;
    *.gz)               gunzip "$file" ;;
    *.zip)              unzip "$file" ;;
    *.z)                uncompress "$file" ;;
    *.7z)               7z x "$file" ;;
    *.zst)              zstd -d "$file" ;;
    *)
      printf "\033[31m✖ Cannot extract '%s' — unsupported extension.\033[0m\n" "$file" >&2
      return 1
      ;;
  esac
}

# 5. Interactive Package.json Script Selector (FZF)
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
    for fn in take up groot conf clone port gsearch wt y copy paste scratch extract npmr bunr pnpmr dotupdate dotcheck toggle-autols acceptance fa; do
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
