# Create directory or file parent and cd into it (take)
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

# Jump to the root directory of the current git repository (groot)
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
  # Uses Zsh parameter modifiers (:h = parent dirname, :t = basename, :l = lowercase) to avoid subshell forks in loops
  if [[ "$target" =~ ^[0-9]+$ ]] && (( target >= 1 && target <= 10 )); then
    # Check if there is an exact directory name matching this number first (e.g. directory named "2")
    local p="${curr:h}"
    while [ "$p" != "/" ] && [ -n "$p" ]; do
      if [[ "${p:t:l}" == "${target:l}" ]]; then
        cd "$p" || return 1
        return 0
      fi
      p="${p:h}"
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
  local p="${curr:h}"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    if [[ "${p:t:l}" == "${target:l}" ]]; then
      cd "$p" || return 1
      return 0
    fi
    p="${p:h}"
  done

  # Pass 2 - Substring / Prefix match (case-insensitive)
  p="${curr:h}"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    if [[ "${p:t:l}" == *"${target:l}"* ]]; then
      cd "$p" || return 1
      return 0
    fi
    p="${p:h}"
  done

  # 3. Safety fallback: If target was not found as an ancestor, stay put and warn
  printf "\033[31m✖ No ancestor directory matching '%s' found.\033[0m\n" "$target" >&2
  return 1
}

# Tab completion for up: dynamically lists ancestor directory names
_up() {
  local -a ancestors
  local p="${PWD:h}"
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    ancestors+=("${p:t}")
    p="${p:h}"
  done
  _describe 'ancestor directory' ancestors
}
(( $+functions[compdef] )) && compdef _up up

unalias tree lt 2>/dev/null || true

# Smart Directory Tree: 'tree' (full), 'tree 3' (3 levels), 'tree 2 src/' or 'tree src/ 2', 'tree -L 3'
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

  local key="" selected_lines=""
  _fzf_split_expect "$selected" || return 0
  local chosen
  chosen=$(echo "$selected_lines" | awk '{print $2}')
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

# Internal helper: resolve active git branch from a repository root without forking git
_proj_repo_branch() {
  local repo="$1"
  local head_file="$repo/.git/HEAD"
  if [[ -f "$repo/.git" ]]; then
    local gitdir_line=""
    read -r gitdir_line < "$repo/.git" 2>/dev/null
    local gd="${gitdir_line#gitdir: }"
    [[ "$gd" != /* ]] && gd="$repo/$gd"
    head_file="$gd/HEAD"
  fi
  if [[ -f "$head_file" ]]; then
    local head_content=""
    read -r head_content < "$head_file" 2>/dev/null
    if [[ "$head_content" == ref:\ refs/heads/* ]]; then
      printf "%s" "${head_content#ref: refs/heads/}"
      return 0
    elif [[ -n "$head_content" ]]; then
      printf "%s" "${head_content[1,7]}"
      return 0
    fi
  fi
  printf "main"
}

# Internal helper: open a directory in a new terminal tab/window across macOS, Linux & WSL
_open_terminal_tab() {
  local target_dir="${1:-$PWD}"
  if [[ -n "$TMUX" ]]; then
    tmux new-window -c "$target_dir"
  elif [[ -n "$ZELLIJ" ]]; then
    zellij action new-tab --cwd "$target_dir"
  elif [[ "$TERM_PROGRAM" == "WezTerm" ]] && command -v wezterm &>/dev/null; then
    wezterm cli spawn --cwd "$target_dir" >/dev/null
  elif [[ -n "$KITTY_LISTEN_ON" ]] && command -v kitty &>/dev/null; then
    kitty @ launch --type=tab --cwd="$target_dir" >/dev/null
  elif [[ "$OSTYPE" == darwin* ]]; then
    if [[ "$TERM_PROGRAM" == "ghostty" || -d "/Applications/Ghostty.app" ]]; then
      osascript - "$target_dir" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set targetDir to item 1 of argv
  tell application "Ghostty"
    set cfg to new surface configuration
    set initial working directory of cfg to targetDir
    if (count of windows) > 0 then
      new tab in front window with configuration cfg
    else
      new window with configuration cfg
    end if
    activate
  end tell
end run
APPLESCRIPT
    elif [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
      open -a iTerm "$target_dir"
    else
      open -a Terminal "$target_dir"
    fi
  elif [[ -n "$WT_SESSION" ]] && command -v wt.exe &>/dev/null; then
    wt.exe -w 0 nt -d "$target_dir"
  elif command -v gnome-terminal &>/dev/null; then
    gnome-terminal --tab --working-directory="$target_dir"
  elif command -v konsole &>/dev/null; then
    konsole --new-tab --workdir "$target_dir"
  elif command -v xfce4-terminal &>/dev/null; then
    xfce4-terminal --tab --working-directory="$target_dir"
  else
    cd "$target_dir"
  fi
}

# Internal helper: list discovered Git repositories under ~/Codes (or $DOTFILES_PROJECTS_DIR) and ~/.dotfiles
# Uses search-root-relative names (e.g. `sales/ui/develop`, `sales/service/develop`, `CRM/service`)
# so worktrees and multi-repo layouts sharing branch names like `develop` are always unambiguous.
# Output format: <relative_name>\t<branch>\t<path>
_proj_list_repos() {
  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local -a search_dirs=()
  if [[ -n "$DOTFILES_PROJECTS_DIR" ]]; then
    search_dirs=(${(s.:.)DOTFILES_PROJECTS_DIR})
  else
    local d
    for d in "$HOME/Codes" "$HOME/Projects" "$HOME/repos" "$HOME/src"; do
      [[ -d "$d" ]] && search_dirs+=("$d")
    done
  fi

  local -A seen_paths=()
  local sdir entry repo rel_name branch
  local -a sdir_entries=()

  for sdir in "${search_dirs[@]}"; do
    [[ -d "$sdir" ]] || continue
    sdir="${sdir%/}"
    if command -v fd &>/dev/null; then
      sdir_entries=(${(f)"$(fd --hidden --no-ignore -g '.git' --max-depth 4 "$sdir" 2>/dev/null)"})
    else
      sdir_entries=(${(f)"$(find "$sdir" -maxdepth 4 -name '.git' 2>/dev/null)"})
    fi
    for entry in "${sdir_entries[@]}"; do
      [[ -z "$entry" ]] && continue
      entry="${entry%/}"
      repo="${entry:h}"
      [[ -z "$repo" || ! -d "$repo" ]] && continue
      (( ${+seen_paths[$repo]} )) && continue
      seen_paths[$repo]=1
      rel_name="${repo#${sdir}/}"
      [[ -z "$rel_name" || "$rel_name" == "$repo" ]] && rel_name="${repo:t}"
      branch="$(_proj_repo_branch "$repo")"
      printf "%s\t%s\t%s\n" "$rel_name" "$branch" "$repo"
    done
  done

  if [[ -e "$dot_dir/.git" ]] && (( ! ${+seen_paths[$dot_dir]} )); then
    seen_paths[$dot_dir]=1
    branch="$(_proj_repo_branch "$dot_dir")"
    printf "%s\t%s\t%s\n" "${dot_dir:t}" "$branch" "$dot_dir"
  fi
}

# Interactive Git Project & Repository Switcher (proj / fp)
# Scans ~/Codes (or $DOTFILES_PROJECTS_DIR) and ~/.dotfiles for Git repositories & worktrees
# Usage:
#   proj / fp          -> Browse all discovered Git projects in modal-Vim FZF
#   proj <name>        -> Jump directly to matching project (or open FZF filtered by <name>)
#   proj -l, --list    -> List discovered projects (<name>\t<branch>\t<path>)
#   Keys: enter = cd, e = open in $EDITOR, l = open lazygit, t = open in new terminal tab, y = copy path
proj() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;137;180;250mproj\033[0m (alias: \033[1mfp\033[0m) — Interactive modal-Vim Git project & repository switcher\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  proj / fp          Browse all Git repositories in ~/Codes & ~/.dotfiles\n"
    printf "  proj <name>        Jump directly to <name> (or filter in FZF if multiple match)\n"
    printf "  proj -l, --list    Print tab-separated table of discovered projects\n"
    printf "  Enter              cd into selected repository\n"
    printf "  e                  Open repository in \$EDITOR (nvim)\n"
    printf "  l                  Open lazygit in selected repository\n"
    printf "  t                  Open repository in a new terminal tab\n"
    printf "  y                  Copy repository path to clipboard\n"
    return 0
  fi

  local list_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  fi

  local rows
  rows="$(_proj_list_repos | sort -f -k1,1)"
  if [[ -z "$rows" ]]; then
    printf "\033[33mNo Git repositories found in %s.\033[0m\n" "${DOTFILES_PROJECTS_DIR:-$HOME/Codes}" >&2
    return 1
  fi

  local query="$*"

  # Direct jump when a query uniquely matches a project's relative name or leaf basename
  if [[ "$list_only" == false && -n "$query" ]]; then
    local n b p leaf
    local -a exact_rel_paths=() exact_leaf_paths=() substring_paths=()
    while IFS=$'\t' read -r n b p; do
      leaf="${n:t}"
      if [[ "${n:l}" == "${query:l}" ]]; then
        exact_rel_paths+=("$p")
      fi
      if [[ "${leaf:l}" == "${query:l}" ]]; then
        exact_leaf_paths+=("$p")
      fi
      if [[ "${n:l}" == *"${query:l}"* ]]; then
        substring_paths+=("$p")
      fi
    done <<< "$rows"

    if (( ${#exact_rel_paths[@]} == 1 )) && [[ -d "${exact_rel_paths[1]}" ]]; then
      cd "${exact_rel_paths[1]}"
      return 0
    elif (( ${#exact_leaf_paths[@]} == 1 )) && [[ -d "${exact_leaf_paths[1]}" ]]; then
      cd "${exact_leaf_paths[1]}"
      return 0
    elif (( ${#substring_paths[@]} == 1 )) && [[ ! -t 1 || ! -x "$(command -v fzf)" ]]; then
      cd "${substring_paths[1]}"
      return 0
    fi
  fi

  if [[ "$list_only" == true || ! -t 1 ]] || ! command -v fzf &>/dev/null; then
    if [[ -n "$query" ]]; then
      printf "%s\n" "$rows" | grep -i "$query"
    else
      printf "%s\n" "$rows"
    fi
    return 0
  fi

  local formatted
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' -v home="$HOME" '
    {
      rel = $1;
      branch = $2;
      full = $3;
      if (length(rel) > 38) rel = substr(rel, 1, 35) "...";
      if (length(branch) > 36) branch = substr(branch, 1, 33) "...";
      disp_path = full;
      if (index(disp_path, home) == 1) {
        disp_path = "~" substr(disp_path, length(home) + 1);
      }
      rels[NR] = rel;
      branches[NR] = branch;
      disps[NR] = disp_path;
      fulls[NR] = full;
      if (length(rel) > w_rel) w_rel = length(rel);
      if (length(branch) > w_br) w_br = length(branch);
    }
    END {
      if (w_rel < 20) w_rel = 20;
      if (w_br < 16) w_br = 16;
      for (r = 1; r <= NR; r++) {
        rel = rels[r];
        branch = branches[r];
        disp_path = disps[r];
        full = fulls[r];
        slash_idx = 0;
        for (i = length(rel); i >= 1; i--) {
          if (substr(rel, i, 1) == "/") { slash_idx = i; break; }
        }
        pad = (w_rel + 2) - length(rel);
        if (pad < 1) pad = 1;
        spaces = sprintf("%*s", pad, "");
        if (slash_idx > 0) {
          prefix = substr(rel, 1, slash_idx);
          leaf = substr(rel, slash_idx + 1);
          name_col = sprintf("\033[38;2;203;166;247m%s\033[1;38;2;137;180;250m%s\033[0m%s", prefix, leaf, spaces);
        } else {
          name_col = sprintf("\033[1;38;2;137;180;250m%s\033[0m%s", rel, spaces);
        }
        printf "%s\t\033[38;2;166;227;161m %-*s\033[0m\t\033[2m%s\033[0m\t%s\n", name_col, w_br, branch, disp_path, full
      }
    }
  ')

  local hdr="  j/k: navigate │ /: search │ enter: cd │ e: edit │ l: lazygit │ t: new tab │ y: copy path │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "🚀 Projects > " "$hdr" "cd" "e,l,t,y" "$query"

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --height=~55% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:blue,pointer:bold:green" \
    --preview='p={4}; git -C "$p" status -sb 2>/dev/null; echo ""; git -C "$p" log --oneline --graph --decorate --color=always -n 8 2>/dev/null; echo ""; if command -v eza &>/dev/null; then eza --tree --level=2 --icons --color=always "$p" 2>/dev/null; else ls -la "$p" 2>/dev/null; fi' \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selection" || return 0
  local chosen_line="${selected_lines%%$'\n'*}"
  local chosen="${chosen_line##*$'\t'}"
  [[ -z "$chosen" || ! -d "$chosen" ]] && return 0

  case "$key" in
    e)
      (cd "$chosen" && "${EDITOR:-nvim}" .)
      ;;
    l)
      if command -v lazygit &>/dev/null; then
        lazygit -p "$chosen"
      else
        cd "$chosen"
      fi
      ;;
    t)
      _open_terminal_tab "$chosen"
      ;;
    y)
      _copy_or_print "$chosen" "project path: $chosen"
      ;;
    *)
      cd "$chosen"
      ;;
  esac
}

# Tab completion for proj / fp: dynamically completes discovered Git repository names
_proj() {
  local -a repos
  local n b p
  while IFS=$'\t' read -r n b p; do
    [[ -n "$n" ]] && repos+=("${n//:/\\:}:${b} (${p/#$HOME/~})")
  done < <(_proj_list_repos)
  (( ${#repos[@]} )) && _describe 'git project' repos
}
(( $+functions[compdef] )) && compdef _proj proj || true

# Cross-Platform Path Translator (wpath) — WSL <-> Windows, file:// URIs & Drag-and-Drop Paths
# Usage:
#   wpath 'C:\Users\me\Desktop'   -> /mnt/c/Users/me/Desktop
#   wpath -w /mnt/c/Users/me      -> C:\Users\me
#   wpath -c [path]               -> Translate path (defaults to $PWD) and copy to clipboard
wpath() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;137;180;250mwpath\033[0m — Cross-platform WSL <-> Windows & URI path translator\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  wpath <path>          Auto-translate Windows path -> Unix (or Unix -> host path)\n"
    printf "  wpath -u <path>       Convert Windows / file:// path to POSIX path\n"
    printf "  wpath -w [path]       Convert POSIX path to Windows path (C:\\...)\n"
    printf "  wpath -c [path]       Copy translated path to clipboard\n"
    return 0
  fi

  local mode="auto"
  local copy_out=false
  while [[ "$1" == -* ]]; do
    case "$1" in
      -u|--unix)    mode="unix"; shift ;;
      -w|--windows) mode="win"; shift ;;
      -c|--copy)    copy_out=true; shift ;;
      --)           shift; break ;;
      *)            break ;;
    esac
  done

  local raw="${1:-$PWD}"
  # Strip surrounding quotes if pasted with literal quotes
  if [[ ( "$raw" == \"*\" && "$raw" == *\" ) || ( "$raw" == \'*\' && "$raw" == *\' ) ]]; then
    raw="${raw[2,-2]}"
  fi
  # Strip file:// prefix
  raw="${raw#file://}"

  local out=""
  if [[ "$mode" == "auto" ]]; then
    if [[ "$raw" =~ ^[A-Za-z]:[\\/] || "$raw" == \\\\* ]]; then
      mode="unix"
    elif [[ -n "$WSL_DISTRO_NAME" ]]; then
      mode="win"
    else
      mode="unix"
    fi
  fi

  if [[ "$mode" == "unix" ]]; then
    if [[ -n "$WSL_DISTRO_NAME" ]] && command -v wslpath &>/dev/null && [[ "$raw" =~ ^[A-Za-z]:[\\/] || "$raw" == \\\\* ]]; then
      out="$(wslpath -u "$raw" 2>/dev/null)"
    fi
    if [[ -z "$out" ]]; then
      if [[ "$raw" =~ ^([A-Za-z]):[\\/](.*)$ ]]; then
        local drive="${match[1]:l}"
        local rest="${match[2]//\\//}"
        out="/mnt/${drive}/${rest}"
      elif [[ "$raw" =~ ^([A-Za-z]):$ ]]; then
        out="/mnt/${match[1]:l}"
      else
        out="$raw"
      fi
    fi
  else
    if [[ -n "$WSL_DISTRO_NAME" ]] && command -v wslpath &>/dev/null; then
      out="$(wslpath -w "$raw" 2>/dev/null)"
    fi
    if [[ -z "$out" ]]; then
      if [[ "$raw" =~ ^/mnt/([a-zA-Z])(/.*)?$ ]]; then
        local drive="${match[1]:u}"
        local rest="${match[2]:-}"
        rest="${rest#/}"
        rest="${rest//\//\\}"
        out="${drive}:\\${rest}"
      else
        out="${raw//\//\\}"
      fi
    fi
  fi

  if [[ "$copy_out" == true ]]; then
    _copy_or_print "$out" "path: $out"
  else
    printf "%s\n" "$out"
  fi
}

# Jump to a Windows, file://, or Drag-and-Drop Path (wcd)
# Reads from clipboard if no path argument is supplied
wcd() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;137;180;250mwcd\033[0m — cd into a Windows (C:\\...), file://, or clipboard path\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  wcd 'C:\\Users\\me\\Project'   Convert Windows path and cd into it\n"
    printf "  wcd file:///path/to/file.ts   cd into parent directory of file URI\n"
    printf "  wcd                           Convert path currently in clipboard and cd into it\n"
    return 0
  fi

  local raw="$1"
  if [[ -z "$raw" ]]; then
    raw="$(clippaste 2>/dev/null)"
    raw="${raw%$'\r'}"
    raw="${raw%$'\n'}"
  fi
  if [[ -z "$raw" ]]; then
    printf "\033[31m✖ Provide a path or copy one to the clipboard first.\033[0m\n" >&2
    return 1
  fi

  local target
  target="$(wpath -u "$raw")"
  target="${target/#\~/$HOME}"
  if [[ -f "$target" ]]; then
    target="${target:h}"
  fi
  if [[ ! -d "$target" ]]; then
    printf "\033[31m✖ Directory does not exist: %s\033[0m\n" "$target" >&2
    return 1
  fi
  cd "$target"
}

