# Git & Worktree Helpers

clone() {
  local repo=$1
  echo "Cloning $repo - git clone git@github.com:$repo.git"
  git clone "git@github.com:$repo.git"
}

gsearch() {
  git log --all --grep="$1" --oneline
}

# Interactive Git Graph & Diff Browser (gl)
# Browses the commit graph interactively with live side-by-side diff previews.
# Supports Enter (pager diff), Ctrl-V (Neovim Diffview), Ctrl-Y (copy hash), and Tab (range diff).
gl() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  # Fall back to standard git log if stdout is not a TTY or if flags starting with '-' are passed
  local has_flags=0
  for arg in "$@"; do
    if [[ "$arg" == -* ]]; then
      has_flags=1
      break
    fi
  done

  if [ ! -t 1 ] || [ $has_flags -eq 1 ] || ! command -v fzf &>/dev/null; then
    git log --oneline --graph --decorate "$@"
    return $?
  fi

  local git_log_cmd
  if [ $# -gt 0 ]; then
    git_log_cmd="git log --graph --color=always --format='%C(auto)%h%d %s %C(dim white)%cr %C(dim cyan)<%an>%Creset' \"$@\""
  else
    git_log_cmd="git log --graph --color=always --format='%C(auto)%h%d %s %C(dim white)%cr %C(dim cyan)<%an>%Creset' --exclude='refs/heads/dura/*' --all"
  fi

  local preview_cmd='h=$(echo {} | grep -oE "[a-f0-9]{7,40}" | head -n1); if [ -n "$h" ]; then if command -v delta &>/dev/null; then git show --stat -p "$h" 2>/dev/null | delta --paging=never --width="${FZF_PREVIEW_COLUMNS:-80}"; else git show --color=always --stat -p "$h" 2>/dev/null; fi; fi'

  selection=$(eval "$git_log_cmd" | fzf \
    --ansi \
    --multi \
    --layout=reverse \
    --border=rounded \
    --disabled \
    --prompt="📜 Git Graph > " \
    --header="j/k: move • /: search • Enter: diff • Ctrl-V: nvim diffview • Ctrl-Y: copy hash • q: quit" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    --bind="start:unbind(esc)" \
    --bind="j:down,k:up,q:abort,g:first,G:last" \
    --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: diff)+rebind(esc)" \
    --bind="i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: diff)+rebind(esc)" \
    --bind="esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(📜 Git Graph > )+change-header(j/k: move • /: search • Enter: diff • Ctrl-V: nvim diffview • Ctrl-Y: copy hash • q: quit)+unbind(esc)" \
    --bind="ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up" \
    --preview="$preview_cmd" \
    --preview-window="right:60%:wrap" \
    --expect="ctrl-v,ctrl-y")

  local exit_code=$?
  [ $exit_code -ne 0 ] && return 0
  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_lines
  selected_lines=$(echo "$selection" | sed '1d')

  [ -z "$selected_lines" ] && return 0

  local hashes=()
  while IFS= read -r line; do
    local h
    h=$(echo "$line" | grep -oE "[a-f0-9]{7,40}" | head -n1)
    [ -n "$h" ] && hashes+=("$h")
  done <<< "$selected_lines"

  [ ${#hashes[@]} -eq 0 ] && return 0

  case "$key" in
    ctrl-y)
      local joined_hashes="${(j: :)hashes}"
      if command -v pbcopy &>/dev/null; then
        echo -n "$joined_hashes" | pbcopy
        printf "\033[32m✔ Copied hash(es) to clipboard: %s\033[0m\n" "$joined_hashes"
      elif command -v wl-copy &>/dev/null; then
        echo -n "$joined_hashes" | wl-copy
        printf "\033[32m✔ Copied hash(es) to clipboard: %s\033[0m\n" "$joined_hashes"
      elif command -v xclip &>/dev/null; then
        echo -n "$joined_hashes" | xclip -selection clipboard
        printf "\033[32m✔ Copied hash(es) to clipboard: %s\033[0m\n" "$joined_hashes"
      else
        printf "%s\n" "$joined_hashes"
      fi
      ;;
    ctrl-v)
      if command -v nvim &>/dev/null; then
        if [ ${#hashes[@]} -ge 2 ]; then
          local from="${hashes[-1]}"
          local to="${hashes[1]}"
          nvim -c "DiffviewOpen ${from}~1..${to}"
        else
          local commit="${hashes[1]}"
          nvim -c "DiffviewOpen ${commit}~1..${commit}"
        fi
      else
        printf "\033[31m✖ Neovim (nvim) is not installed.\033[0m\n" >&2
      fi
      ;;
    *)
      if [ ${#hashes[@]} -ge 2 ]; then
        local from="${hashes[-1]}"
        local to="${hashes[1]}"
        git diff "${from}~1..${to}"
      else
        local commit="${hashes[1]}"
        git show --stat -p "$commit"
      fi
      ;;
  esac
}

# Interactive Git Checkout / Branch Switcher (gco)
# When run with arguments: passes directly to git checkout "$@"
# When run without arguments: opens interactive branch switcher with vim motions & log preview
gco() {
  if [ $# -gt 0 ] || [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    git checkout "$@"
    return $?
  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    git checkout
    return $?
  fi

  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null)"

  local branches=()
  while IFS= read -r b; do
    local b_clean="$(echo "$b" | sed 's/^[ *+]*//')"
    [[ -z "$b_clean" || "$b_clean" == "$current_branch" || "$b_clean" == "HEAD"* || "$b_clean" == dura/* ]] && continue
    branches+=("$b_clean")
  done < <(git branch --format='%(refname:short)' 2>/dev/null)

  if [ "${#branches[@]}" -eq 0 ]; then
    printf "\033[33mNo other local branches found to switch to.\033[0m\n"
    return 0
  fi

  local target
  target=$(printf "%s\n" "${branches[@]}" | fzf \
    --height=~45% \
    --layout=reverse \
    --border=rounded \
    --disabled \
    --pointer="❯ " \
    --prompt="🌿 Checkout Branch > " \
    --header="  j/k: navigate │ /: search │ enter: checkout │ q: quit" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:cyan" \
    --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept" \
    --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: checkout)+rebind(esc)" \
    --bind="i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: checkout)+rebind(esc)" \
    --bind="esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(🌿 Checkout Branch > )+change-header(  j/k: navigate │ /: search │ enter: checkout │ q: quit)+unbind(esc)" \
    --bind="start:unbind(esc)" \
    --preview='git log -n 10 --oneline --color=always {} 2>/dev/null' \
    --preview-window='right:55%:wrap')

  if [ -n "$target" ]; then
    git checkout "$target"
  fi
}

# Interactive Git Stash Manager (gstash / gstl)
# When run with arguments: passes directly to git stash "$@"
# When run without arguments: opens modal-Vim FZF stash browser with live diff preview
# Keys: enter = apply, p = pop, x = drop (multi-select supported for drop)
gstash() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mgstash\033[0m (alias: \033[1mgstl\033[0m) — Interactive modal-Vim Git stash browser\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  gstash             Open interactive stash picker (enter: apply, p: pop, x: drop)\n"
    printf "  gstash <args...>   Pass arguments directly to 'git stash <args...>'\n"
    return 0
  fi

  if [ $# -gt 0 ]; then
    git stash "$@"
    return $?
  fi

  local stashes
  stashes="$(git stash list --color=always 2>/dev/null)"
  if [ -z "$stashes" ]; then
    printf "\033[33mNo git stashes found in this repository.\033[0m\n"
    return 0
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "%s\n" "$stashes"
    return 0
  fi

  local selection
  selection=$(printf "%s\n" "$stashes" | fzf \
    --ansi \
    --multi \
    --height=~50% \
    --layout=reverse \
    --border=rounded \
    --disabled \
    --pointer="❯ " \
    --marker="✓ " \
    --prompt="📦 Git Stashes > " \
    --header="  j/k: navigate │ /: search │ enter: apply │ p: pop │ space+x: drop │ q: quit" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:cyan,marker:bold:red" \
    --bind="start:unbind(esc)" \
    --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,space:toggle+down" \
    --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,space,i,/)+change-prompt(🔍 Search Stashes > )+change-header(  type to filter │ esc: normal mode │ enter: apply)+rebind(esc)" \
    --bind="i:enable-search+unbind(j,k,q,g,G,space,i,/)+change-prompt(🔍 Search Stashes > )+change-header(  type to filter │ esc: normal mode │ enter: apply)+rebind(esc)" \
    --bind="esc:disable-search+rebind(j,k,q,g,G,space,i,/)+change-prompt(📦 Git Stashes > )+change-header(  j/k: navigate │ /: search │ enter: apply │ p: pop │ space+x: drop │ q: quit)+unbind(esc)" \
    --bind="ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up" \
    --preview='s=$(echo {} | grep -oE "stash@\{[0-9]+\}" | head -n1); if [ -n "$s" ]; then if command -v delta &>/dev/null; then git stash show --stat -p "$s" 2>/dev/null | delta --paging=never --width="${FZF_PREVIEW_COLUMNS:-80}"; else git stash show --color=always --stat -p "$s" 2>/dev/null; fi; fi' \
    --preview-window="right:60%:wrap" \
    --expect="p,x")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_lines
  selected_lines=$(echo "$selection" | sed '1d')
  [ -z "$selected_lines" ] && return 0

  local refs=()
  while IFS= read -r line; do
    local r
    r=$(echo "$line" | grep -oE 'stash@\{[0-9]+\}' | head -n1)
    [ -n "$r" ] && refs+=("$r")
  done <<< "$selected_lines"

  [ ${#refs[@]} -eq 0 ] && return 0

  case "$key" in
    p)
      git stash pop "${refs[1]}"
      ;;
    x)
      # Drop in reverse index order so stash@{N} indices don't shift mid-loop
      local -a sorted_refs
      sorted_refs=($(printf "%s\n" "${refs[@]}" | sort -t'{' -k2 -rn))
      for r in "${sorted_refs[@]}"; do
        git stash drop "$r"
      done
      ;;
    *)
      git stash apply "${refs[1]}"
      ;;
  esac
}

# Interactive Git File Stage / Unstage / Discard Picker (ga / gadd)
# When run with arguments: passes directly to git add "$@"
# When run without arguments: opens modal-Vim FZF picker for modified/staged/untracked files
unalias ga 2>/dev/null || true

ga() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mga\033[0m (alias: \033[1mgadd\033[0m) — Interactive modal-Vim Git stage / unstage / discard picker\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  ga                 Open interactive file picker (enter: stage, u: unstage, x: discard, e: edit)\n"
    printf "  ga <files...>      Pass arguments directly to 'git add <files...>'\n"
    return 0
  fi

  if [ $# -gt 0 ]; then
    git add "$@"
    return $?
  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local status_lines
  status_lines="$(git -c color.status=always status --short 2>/dev/null)"
  if [ -z "$status_lines" ]; then
    printf "\033[32m✔ Working tree is clean — nothing to stage or unstage.\033[0m\n"
    return 0
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    git status -sb
    return 0
  fi

  local preview_cmd='
    clean=$(echo {} | sed "s/\x1b\[[0-9;]*m//g")
    st="${clean:0:2}"
    f=$(echo "$clean" | sed -E "s/^.. //; s/.* -> //; s/^\"(.*)\"$/\1/")
    if [ "$st" = "??" ]; then
      if [ -d "$f" ]; then
        if command -v eza &>/dev/null; then eza --tree --level=2 --icons --color=always "$f"; else ls -la "$f"; fi
      elif command -v bat &>/dev/null; then
        bat --color=always --style=numbers --line-range :300 "$f" 2>/dev/null
      else
        cat "$f" 2>/dev/null
      fi
    elif command -v delta &>/dev/null; then
      { git diff -- "$f" 2>/dev/null; git diff --staged -- "$f" 2>/dev/null; } | delta --paging=never --width="${FZF_PREVIEW_COLUMNS:-80}"
    else
      git diff --color=always -- "$f" 2>/dev/null
      git diff --staged --color=always -- "$f" 2>/dev/null
    fi
  '

  local selection
  selection=$(printf "%s\n" "$status_lines" | fzf \
    --ansi \
    --multi \
    --height=~55% \
    --layout=reverse \
    --border=rounded \
    --disabled \
    --pointer="❯ " \
    --marker="✓ " \
    --prompt="📂 Git Stage/Unstage > " \
    --header="  j/k: move │ space: select │ enter: stage │ u: unstage │ x: discard │ e: edit │ /: search │ q: quit" \
    --color="header:italic:dim,prompt:bold:green,pointer:bold:cyan,marker:bold:yellow" \
    --bind="start:unbind(esc)" \
    --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,space:toggle+down" \
    --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,space,u,x,e,i,/)+change-prompt(🔍 Search Files > )+change-header(  type to filter │ esc: normal mode │ enter: stage)+rebind(esc)" \
    --bind="i:enable-search+unbind(j,k,q,g,G,space,u,x,e,i,/)+change-prompt(🔍 Search Files > )+change-header(  type to filter │ esc: normal mode │ enter: stage)+rebind(esc)" \
    --bind="esc:disable-search+rebind(j,k,q,g,G,space,u,x,e,i,/)+change-prompt(📂 Git Stage/Unstage > )+change-header(  j/k: move │ space: select │ enter: stage │ u: unstage │ x: discard │ e: edit │ /: search │ q: quit)+unbind(esc)" \
    --bind="ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up" \
    --preview="$preview_cmd" \
    --preview-window="right:60%:wrap" \
    --expect="u,x,e")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_lines
  selected_lines=$(echo "$selection" | sed '1d')
  [ -z "$selected_lines" ] && return 0

  local -a files untracked_files tracked_files
  while IFS= read -r line; do
    local clean_line st fpath
    clean_line=$(printf "%s" "$line" | sed $'s/\x1b\\[[0-9;]*m//g')
    st="${clean_line:0:2}"
    fpath=$(printf "%s" "$clean_line" | sed -E 's/^.. //; s/.* -> //; s/^"(.*)"$/\1/')
    if [ -n "$fpath" ]; then
      files+=("$fpath")
      if [ "$st" = "??" ]; then
        untracked_files+=("$fpath")
      else
        tracked_files+=("$fpath")
      fi
    fi
  done <<< "$selected_lines"

  [ ${#files[@]} -eq 0 ] && return 0

  case "$key" in
    u)
      git restore --staged -- "${files[@]}"
      printf "\033[33m↺ Unstaged %d file(s):\033[0m %s\n" "${#files[@]}" "${(j:, :)files}"
      git status -sb
      ;;
    x)
      printf "\033[1;31m⚠ Discard working-tree changes to %d file(s) (%s)? [y/N]: \033[0m" "${#files[@]}" "${(j:, :)files}"
      local confirm=""
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        [ ${#tracked_files[@]} -gt 0 ] && git checkout -- "${tracked_files[@]}"
        [ ${#untracked_files[@]} -gt 0 ] && rm -rf -- "${untracked_files[@]}"
        printf "\033[32m✔ Discarded changes to %d file(s).\033[0m\n" "${#files[@]}"
        git status -sb
      else
        printf "\033[2mCancelled.\033[0m\n"
      fi
      ;;
    e)
      "${EDITOR:-nvim}" "${files[@]}"
      ;;
    *)
      git add -- "${files[@]}"
      printf "\033[32m✔ Staged %d file(s):\033[0m %s\n" "${#files[@]}" "${(j:, :)files}"
      git status -sb
      ;;
  esac
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
    local fzf_mode_flags=()
    if [ -z "$query" ]; then
      fzf_mode_flags=(
        "--disabled"
        "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept"
        "--bind=/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: cd)+rebind(esc)"
        "--bind=i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: cd)+rebind(esc)"
        "--bind=esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(🌿 Worktree > )+change-header(  j/k: navigate │ /: search │ enter: cd │ q: quit)+unbind(esc)"
        "--bind=start:unbind(esc)"
      )
    else
      fzf_mode_flags=("--query=$query")
    fi

    local selected
    selected=$(echo "$worktrees" | fzf \
      --height=~40% \
      --layout=reverse \
      --border=rounded \
      "${fzf_mode_flags[@]}" \
      --prompt="🌿 Worktree > " \
      --header="  j/k: navigate │ /: search │ enter: cd │ q: quit" \
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

# Git Worktree New / Create (gwtnew / gwtn)
# Creates a new worktree from an existing remote branch or a new branch
gwtnew() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local common_dir
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  local main_root
  if [ -n "$common_dir" ]; then
    main_root="$(cd "$common_dir/.." && pwd)"
  else
    main_root="$(git rev-parse --show-toplevel)"
  fi

  # Determine default base branch (develop if exists, otherwise main or master)
  local base_branch="main"
  if git show-ref --verify --quiet refs/heads/develop || git show-ref --verify --quiet refs/remotes/origin/develop; then
    base_branch="develop"
  elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
    base_branch="master"
  fi

  local target_input="$1"
  target_input="${target_input#"${target_input%%[![:space:]]*}"}"
  target_input="${target_input%"${target_input##*[![:space:]]}"}"

  # If no argument given, offer interactive FZF selection of remote branches
  if [ -z "$target_input" ]; then
    if ! command -v fzf &>/dev/null; then
      printf "Usage: gwtnew <branch-name-or-ticket>\n" >&2
      return 1
    fi

    printf "\033[1;34m==>\033[0m Fetching remote branches...\n"
    git fetch --prune 2>/dev/null || true

    # Collect existing active worktree branches to exclude
    local existing_wts
    existing_wts=$(git worktree list 2>/dev/null | awk '{print $3}' | tr -d '[]')

    # Get remote branches excluding HEAD and already checked-out branches
    local remote_branches=()
    while IFS= read -r b; do
      local b_clean="${b#origin/}"
      [[ "$b_clean" == "HEAD"* ]] && continue
      if echo "$existing_wts" | grep -qx "$b_clean"; then
        continue
      fi
      remote_branches+=("$b_clean")
    done < <(git branch -r 2>/dev/null | sed 's/^[ *]*//')

    if [ "${#remote_branches[@]}" -eq 0 ]; then
      printf "\033[33mNo unattached remote branches found. Provide a branch name to create a new one.\033[0m\n"
      printf "Usage: gwtnew <new-branch-name>\n"
      return 0
    fi

    local fzf_raw
    fzf_raw=$(printf "%s\n" "${remote_branches[@]}" | fzf \
      --print-query \
      --height=~45% \
      --layout=reverse \
      --border=rounded \
      --disabled \
      --pointer="❯ " \
      --prompt="🌱 New Worktree from Branch > " \
      --header="  j/k: navigate │ /: search / type new branch │ enter: select or create │ q: quit" \
      --color="header:italic:dim,prompt:bold:green,pointer:bold:green" \
      --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept" \
      --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search / New Branch > )+change-header(  type branch name │ esc: normal mode │ enter: select or create)+rebind(esc)" \
      --bind="i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search / New Branch > )+change-header(  type branch name │ esc: normal mode │ enter: select or create)+rebind(esc)" \
      --bind="esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(🌱 New Worktree from Branch > )+change-header(  j/k: navigate │ /: search / type new branch │ enter: select or create │ q: quit)+unbind(esc)" \
      --bind="start:unbind(esc)" \
      --preview='git log -n 10 --oneline --color=always "origin/{}" 2>/dev/null' \
      --preview-window='right:55%:wrap')

    local query_line selected_line
    query_line=$(echo "$fzf_raw" | sed -n '1p')
    selected_line=$(echo "$fzf_raw" | sed -n '2p')

    # If an existing branch was selected from the list, use it; otherwise use the typed new branch name
    if [ -n "$selected_line" ]; then
      target_input="$selected_line"
    elif [ -n "$query_line" ]; then
      target_input="$query_line"
    else
      return 0
    fi

    # Strip leading and trailing whitespace
    target_input="${target_input#"${target_input%%[![:space:]]*}"}"
    target_input="${target_input%"${target_input##*[![:space:]]}"}"

    if [ -z "$target_input" ]; then
      return 0
    fi
  fi

  # Resolve branch and directory name
  local target_branch="$target_input"
  local target_folder=""

  # Check if target_input matches an existing remote branch (e.g. "3549" -> "origin/feat/SALES-3549/...")
  local matched_remote
  matched_remote=$(git branch -r 2>/dev/null | sed 's/^[ *]*//' | grep -v 'HEAD' | grep -i "${target_input}" | head -n 1)

  if [ -n "$matched_remote" ]; then
    target_branch="${matched_remote#origin/}"
  fi

  # If purely numeric, format as ticket branch default if not matched
  if [[ "$target_branch" =~ ^[0-9]+$ ]]; then
    target_branch="feat/SALES-${target_branch}"
  fi

  # Determine folder name: extract Jira ticket key (e.g. SALES-3549) if present
  if [[ "$target_branch" =~ ([A-Za-z]+-[0-9]+) ]]; then
    target_folder="${match[1]:u}"
  else
    target_folder="$(basename "$target_branch")"
  fi

  local target_wt_path="$main_root/$target_folder"

  # Check if worktree directory already exists
  if [ -d "$target_wt_path" ]; then
    printf "\033[33m⚠ Directory already exists:\033[0m %s\n" "$target_wt_path"
    if git worktree list 2>/dev/null | grep -q "^$target_wt_path"; then
      printf "Switching to existing worktree...\n"
      cd "$target_wt_path" || return 1
      return 0
    fi
  fi

  # Check if branch exists locally or on remote
  local branch_exists=false
  if git show-ref --verify --quiet "refs/heads/$target_branch" || git show-ref --verify --quiet "refs/remotes/origin/$target_branch"; then
    branch_exists=true
  fi

  if [ "$branch_exists" = true ]; then
    printf "\033[1;34m==>\033[0m Creating worktree \033[1m%s\033[0m tracking branch \033[1;36m%s\033[0m...\n" "$target_folder" "$target_branch"
    if git worktree add "$target_wt_path" "$target_branch"; then
      printf "\033[32m✔ Worktree created successfully!\033[0m\n"
      cd "$target_wt_path" || return 1
      return 0
    else
      printf "\033[31m✖ Failed to create worktree.\033[0m\n" >&2
      return 1
    fi
  else
    # New branch: ask or create off base branch
    printf "\033[1;34m==>\033[0m Branch \033[1;36m%s\033[0m does not exist yet.\n" "$target_branch"
    printf "Create new branch \033[1;36m%s\033[0m off \033[1m%s\033[0m in worktree \033[1m%s\033[0m? [Y/n]: " "$target_branch" "$base_branch" "$target_folder"
    local confirm_new
    read -r confirm_new
    case "$confirm_new" in
      [nN]|[nN][oO])
        printf "Aborted.\n"
        return 0
        ;;
      *)
        if git worktree add -b "$target_branch" "$target_wt_path" "$base_branch"; then
          printf "\033[32m✔ Worktree created successfully with new branch '%s'!\033[0m\n" "$target_branch"
          cd "$target_wt_path" || return 1
          return 0
        else
          printf "\033[31m✖ Failed to create worktree.\033[0m\n" >&2
          return 1
        fi
        ;;
    esac
  fi
}

# Git Worktree Fleet Status Dashboard (gwts / gwtstatus)
# Scans all worktrees in the current repo and prints aligned status, branch, and sync state
gwts() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local active_wt
  active_wt="$(git rev-parse --show-toplevel 2>/dev/null)"
  local wt_path wt_branch marker is_active status_out status_str
  local staged unstaged untracked ahead behind upstream_count sync_str
  local wt_name wt_display_branch
  local -a parts

  printf "\n\033[1;38;2;203;166;247m%-3s %-14s %-38s %-16s %s\033[0m\n" "" "WORKTREE" "BRANCH" "SYNC" "WORKING TREE"
  printf "\033[38;2;108;112;134m%s\033[0m\n" "────────────────────────────────────────────────────────────────────────────────────────"

  while IFS= read -r line; do
    wt_path=$(echo "$line" | awk '{print $1}')
    wt_branch=$(echo "$line" | awk '{print $3}' | tr -d '[]')
    [[ "$wt_branch" == "(bare)" || -z "$wt_branch" ]] && continue

    marker="  "
    is_active=false
    if [ "$wt_path" = "$active_wt" ]; then
      marker="\033[1;32m➜ \033[0m"
      is_active=true
    fi

    status_out=$(git -C "$wt_path" status --porcelain 2>/dev/null)
    status_str=""
    if [ -z "$status_out" ]; then
      status_str="\033[32m✔ clean\033[0m"
    else
      staged=$(echo "$status_out" | grep -c '^[MADRC]' || true)
      unstaged=$(echo "$status_out" | grep -c '^.[MD]' || true)
      untracked=$(echo "$status_out" | grep -c '^\?\?' || true)
      parts=()
      (( staged > 0 )) && parts+=("${staged} staged")
      (( unstaged > 0 )) && parts+=("${unstaged} modified")
      (( untracked > 0 )) && parts+=("${untracked} untracked")
      status_str="\033[1;33m●\033[0m \033[33m${(j:, :)parts}\033[0m"
    fi

    sync_str=""
    upstream_count=$(git -C "$wt_path" rev-list --left-right --count HEAD...@{u} 2>/dev/null || true)
    if [ -n "$upstream_count" ]; then
      ahead=$(echo "$upstream_count" | awk '{print $1}')
      behind=$(echo "$upstream_count" | awk '{print $2}')
      if (( ahead > 0 && behind > 0 )); then
        sync_str="\033[33m↑${ahead} ↓${behind}\033[0m"
      elif (( ahead > 0 )); then
        sync_str="\033[32m↑${ahead}\033[0m"
      elif (( behind > 0 )); then
        sync_str="\033[31m↓${behind}\033[0m"
      else
        sync_str="\033[32m✔ synced\033[0m"
      fi
    else
      sync_str="\033[38;2;108;112;134m(no upstream)\033[0m"
    fi

    wt_name="$(basename "$wt_path")"
    local wt_display_branch="$wt_branch"
    if [ "${#wt_display_branch}" -gt 36 ]; then
      wt_display_branch="${wt_display_branch:0:33}..."
    fi

    if [ "$is_active" = true ]; then
      printf "%b\033[1;32m%-14s\033[0m \033[1;36m%-38s\033[0m %-26b %b\n" "$marker" "$wt_name" "$wt_display_branch" "$sync_str" "$status_str"
    else
      printf "%b%-14s \033[2m%-38s\033[0m %-26b %b\n" "$marker" "$wt_name" "$wt_display_branch" "$sync_str" "$status_str"
    fi
  done < <(git worktree list 2>/dev/null)
  printf "\n"
}

# Git Worktree Delete (gwtdel / gwtrm)
# Safely removes an individual worktree and optionally deletes its local branch
gwtdel() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local active_wt target_input="$1" target_wt="" target_branch=""
  local p b br bname item fzf_lines="" selected wt_name is_dirty=false
  local confirm_dirty confirm_del confirm_br
  local -a eligible rm_opts
  active_wt="$(git rev-parse --show-toplevel 2>/dev/null)"

  # Collect eligible worktrees (exclude active worktree, bare repo, and protected branches)
  while IFS= read -r line; do
    p="$(echo "$line" | awk '{print $1}')"
    b="$(echo "$line" | awk '{print $3}' | tr -d '[]')"
    [[ "$b" == "(bare)" || -z "$b" ]] && continue
    # Skip currently active worktree
    [[ "$p" == "$active_wt" ]] && continue
    # Skip protected branches
    [[ "$b" =~ ^(main|master|develop|qa|stage|staging)$ ]] && continue
    eligible+=("${p}|${b}")
  done < <(git worktree list 2>/dev/null)

  if [ "${#eligible[@]}" -eq 0 ]; then
    printf "\033[33mNo disposable worktrees found (excluding active worktree and protected branches).\033[0m\n"
    return 0
  fi

  if [ -n "$target_input" ]; then
    for item in "${eligible[@]}"; do
      p="${item%%|*}"
      bname="$(basename "$p")"
      br="${item##*|}"
      if [[ "${(L)bname}" == *"${(L)target_input}"* ]] || [[ "${(L)br}" == *"${(L)target_input}"* ]]; then
        target_wt="$p"
        target_branch="$br"
        break
      fi
    done

    if [ -z "$target_wt" ]; then
      if [[ "${(L)$(basename "$active_wt")}" == *"${(L)target_input}"* ]]; then
        printf "\033[31m✖ Cannot delete the active worktree (%s). cd to another directory first.\033[0m\n" "$(basename "$active_wt")" >&2
        return 1
      fi
      printf "\033[31m✖ No disposable worktree matching '%s' found.\033[0m\n" "$target_input" >&2
      return 1
    fi
  else
    if ! command -v fzf &>/dev/null; then
      printf "Usage: gwtdel <worktree-name>\n" >&2
      return 1
    fi

    for item in "${eligible[@]}"; do
      p="${item%%|*}"
      br="${item##*|}"
      bname="$(basename "$p")"
      local dirty_flag=""
      [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ] && dirty_flag=" *dirty*"
      fzf_lines+="${bname}\t[${br}]${dirty_flag}\t${p}\n"
    done

    local selected
    selected=$(printf "%b" "$fzf_lines" | fzf \
      --delimiter=$'\t' \
      --with-nth=1,2 \
      --height=~40% \
      --layout=reverse \
      --border=rounded \
      --disabled \
      --prompt="🗑 Delete Worktree > " \
      --header="  j/k: navigate │ /: search │ enter: select to delete │ q: quit" \
      --color="header:italic:dim,prompt:bold:red,pointer:bold:red" \
      --bind="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept" \
      --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: select)+rebind(esc)" \
      --bind="i:enable-search+unbind(j,k,q,g,G,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: select)+rebind(esc)" \
      --bind="esc:disable-search+rebind(j,k,q,g,G,i,/)+change-prompt(🗑 Delete Worktree > )+change-header(  j/k: navigate │ /: search │ enter: select to delete │ q: quit)+unbind(esc)" \
      --bind="start:unbind(esc)" \
      --preview='git -C {3} status -sb 2>/dev/null' \
      --preview-window='right:55%:wrap')

    [ -z "$selected" ] && return 0
    target_wt=$(echo "$selected" | awk -F'\t' '{print $3}')
    for item in "${eligible[@]}"; do
      if [ "${item%%|*}" = "$target_wt" ]; then
        target_branch="${item##*|}"
        break
      fi
    done
  fi

  local wt_name="$(basename "$target_wt")"
  local is_dirty=false
  [ -n "$(git -C "$target_wt" status --porcelain 2>/dev/null)" ] && is_dirty=true

  if [ "$is_dirty" = true ]; then
    printf "\n\033[1;33m⚠ Worktree has uncommitted changes:\033[0m \033[1m%s\033[0m \033[2m[%s]\033[0m\n" "$target_wt" "$target_branch"
    printf "\033[2m───────────────── Output of gs (git status -sb) ─────────────────\033[0m\n"
    git -C "$target_wt" status -sb
    printf "\033[2m─────────────────────────────────────────────────────────────────\033[0m\n"
    printf "\033[1;31mDiscard uncommitted changes and delete this worktree?\033[0m [y/N]: "
    local confirm_dirty
    read -r confirm_dirty
    case "$confirm_dirty" in
      [yY]|[yY][eE][sS]) ;;
      *)
        printf "Aborted. Worktree preserved.\n"
        return 0
        ;;
    esac
  else
    printf "Delete worktree \033[1m%s\033[0m \033[2m[%s]\033[0m? [y/N]: " "$wt_name" "$target_branch"
    local confirm_del
    read -r confirm_del
    case "$confirm_del" in
      [yY]|[yY][eE][sS]) ;;
      *)
        printf "Aborted.\n"
        return 0
        ;;
    esac
  fi

  local rm_opts=()
  [ "$is_dirty" = true ] && rm_opts+=("--force")

  printf "Removing worktree \033[1m%s\033[0m..." "$wt_name"
  if git worktree remove "${rm_opts[@]}" "$target_wt" 2>/dev/null; then
    printf " \033[32m✔\033[0m\n"
    if [ -n "$target_branch" ]; then
      printf "Delete local branch \033[1m%s\033[0m? [Y/n]: " "$target_branch"
      local confirm_br
      read -r confirm_br
      case "$confirm_br" in
        [nN]|[nN][oO]) ;;
        *)
          if git branch -d "$target_branch" 2>/dev/null || git branch -D "$target_branch" 2>/dev/null; then
            printf "  \033[32m✔\033[0m Deleted local branch %s\n" "$target_branch"
          fi
          ;;
      esac
    fi
    git worktree prune 2>/dev/null
    printf "\033[32m✔ Worktree '%s' removed successfully!\033[0m\n" "$wt_name"
  else
    printf " \033[31m✖ Failed to remove worktree.\033[0m\n" >&2
    return 1
  fi
}

# Git Worktree Clean / Prune (gwtclean / gwtprune / gwtc)
# Prunes worktrees whose remote upstream branch has been deleted on the remote
gwtclean() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local force=false
  if [[ "$1" == "-f" || "$1" == "--force" ]]; then
    force=true
  fi

  # Identify main root repository directory
  local common_dir
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  local main_worktree=""
  if [ -n "$common_dir" ]; then
    main_worktree="$(cd "$common_dir/.." && pwd)"
  fi

  printf "\033[1;34m==>\033[0m Fetching and pruning remote branches (git fetch --prune)...\n"
  git fetch --prune 2>/dev/null || {
    printf "\033[33m⚠ Warning: git fetch --prune failed; checking local tracking state...\033[0m\n"
  }

  local candidates=()
  local _wt_path=""
  local _wt_branch=""

  _check_candidate() {
    local p="$1"
    local b="$2"
    if [ -n "$p" ] && [ -n "$b" ] && [ "$p" != "$main_worktree" ]; then
      if git -C "$p" branch -vv --list "$b" 2>/dev/null | grep -q '\[.*: gone\]'; then
        candidates+=("${p}|${b}")
      else
        local upstream_ref
        upstream_ref="$(git -C "$p" config --get "branch.${b}.merge" 2>/dev/null || true)"
        local remote_name
        remote_name="$(git -C "$p" config --get "branch.${b}.remote" 2>/dev/null || true)"
        if [ -n "$upstream_ref" ] && [ -n "$remote_name" ]; then
          local short_ref="${upstream_ref#refs/heads/}"
          if ! git -C "$p" rev-parse --verify "refs/remotes/${remote_name}/${short_ref}" &>/dev/null; then
            candidates+=("${p}|${b}")
          fi
        fi
      fi
    fi
  }

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      worktree\ *)
        _check_candidate "$_wt_path" "$_wt_branch"
        _wt_path="${line#worktree }"
        _wt_branch=""
        ;;
      branch\ refs/heads/*)
        _wt_branch="${line#branch refs/heads/}"
        ;;
      "")
        _check_candidate "$_wt_path" "$_wt_branch"
        _wt_path=""
        _wt_branch=""
        ;;
    esac
  done <<< "$(git worktree list --porcelain)"
  _check_candidate "$_wt_path" "$_wt_branch"

  local count="${#candidates[@]}"
  if [ "$count" -eq 0 ]; then
    printf "\033[32m✔ No worktrees with deleted remote branches found.\033[0m\n"
    git worktree prune
    return 0
  fi

  local selected_candidates=()

  # If force mode, select all candidates automatically
  if [ "$force" = true ]; then
    selected_candidates=("${candidates[@]}")
  elif command -v fzf &>/dev/null && [ -t 1 ]; then
    local fzf_input=""
    local item
    for item in "${candidates[@]}"; do
      local wt_path="${item%%|*}"
      local wt_branch="${item##*|}"
      local dirty_tag=""
      if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
        dirty_tag=" *dirty*"
      fi
      fzf_input+="${wt_path}\t[${wt_branch}]${dirty_tag}\n"
    done

    local fzf_output
    fzf_output=$(printf "%b" "$fzf_input" | fzf \
      --multi \
      --height=~45% \
      --layout=reverse \
      --border=rounded \
      --disabled \
      --pointer="❯ " \
      --marker="✔ " \
      --prompt="🗑 Select Worktrees to Prune > " \
      --header="  j/k: navigate │ space/tab: toggle │ a: toggle all │ /: search │ enter: confirm │ q: abort" \
      --color="header:italic:dim,prompt:bold:red,pointer:bold:red,marker:bold:green" \
      --bind="j:down,k:up,g:first,G:last,space:toggle+down,tab:toggle+down,btab:toggle+up,a:toggle-all,q:abort,ctrl-c:abort,enter:accept" \
      --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,space,a,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ tab: toggle │ esc: normal mode │ enter: confirm)+rebind(esc)" \
      --bind="i:enable-search+unbind(j,k,q,g,G,space,a,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ tab: toggle │ esc: normal mode │ enter: confirm)+rebind(esc)" \
      --bind="esc:disable-search+rebind(j,k,q,g,G,space,a,i,/)+change-prompt(🗑 Select Worktrees to Prune > )+change-header(  j/k: navigate │ space/tab: toggle │ a: toggle all │ /: search │ enter: confirm │ q: abort)+unbind(esc)" \
      --bind="start:unbind(esc)" \
      --preview='git -C {1} status -sb 2>/dev/null; echo ""; git -C {1} log -n 5 --oneline --color=always 2>/dev/null' \
      --preview-window='right:55%:wrap')

    if [ -z "$fzf_output" ]; then
      printf "No worktrees selected. Aborted.\n"
      return 0
    fi

    while IFS= read -r sel_line || [ -n "$sel_line" ]; do
      local sel_path
      sel_path=$(echo "$sel_line" | awk -F'\t' '{print $1}')
      for item in "${candidates[@]}"; do
        if [ "${item%%|*}" = "$sel_path" ]; then
          selected_candidates+=("$item")
          break
        fi
      done
    done <<< "$fzf_output"
  elif [ "$count" -eq 1 ]; then
    # Fallback for single candidate without fzf/TTY
    local item="${candidates[1]}"
    local wt_path="${item%%|*}"
    local wt_branch="${item##*|}"
    printf "\n\033[1;33mFound 1 worktree whose remote tracking branch is gone:\033[0m\n"
    printf "  \033[1;36m•\033[0m %-40s \033[2m[%s]\033[0m\n" "$wt_path" "$wt_branch"
    printf "\nPrune this worktree? [y/N]: "
    local confirm_single
    read -r confirm_single
    case "$confirm_single" in
      [yY]|[yY][eE][sS]) selected_candidates+=("$item") ;;
      *)
        printf "Aborted. No worktrees were removed.\n"
        return 0
        ;;
    esac
  else
    # Fallback text multi-select menu without fzf/TTY
    printf "\n\033[1;33mFound %d worktrees whose remote tracking branches are gone:\033[0m\n" "$count"
      local idx=1
      for item in "${candidates[@]}"; do
        local wt_path="${item%%|*}"
        local wt_branch="${item##*|}"
        local dirty_tag=""
        if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
          dirty_tag=" \033[31m(DIRTY: uncommitted changes)\033[0m"
        fi
        printf "  %2d) %-40s \033[2m[%s]\033[0m%b\n" "$idx" "$wt_path" "$wt_branch" "$dirty_tag"
        ((idx++))
      done

      printf "\nEnter numbers to prune (e.g. 1,2 or 'a' for all, Enter to cancel): "
      local input_choice
      read -r input_choice
      if [ -z "$input_choice" ]; then
        printf "Aborted. No worktrees were removed.\n"
        return 0
      fi

      if [[ "$input_choice" == "a" || "$input_choice" == "all" ]]; then
        selected_candidates=("${candidates[@]}")
      else
        local clean_choices
        clean_choices=$(echo "$input_choice" | tr ',' ' ')
        for num in $clean_choices; do
          if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
            selected_candidates+=("${candidates[$num]}")
          fi
        done
      fi
    fi

  local num_selected="${#selected_candidates[@]}"
  if [ "$num_selected" -eq 0 ]; then
    printf "No valid worktrees selected. Aborted.\n"
    return 0
  fi

  printf "\n\033[1;34m==>\033[0m Processing %d selected worktree(s)...\n" "$num_selected"

  for item in "${selected_candidates[@]}"; do
    local wt_path="${item%%|*}"
    local wt_branch="${item##*|}"

    if [ "$PWD" = "$wt_path" ] || [[ "$PWD" == "$wt_path"/* ]]; then
      printf "  \033[33m⚠ Skipping active worktree (currently inside):\033[0m %s\n" "$wt_path"
      continue
    fi

    local is_dirty=false
    if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
      is_dirty=true
    fi

    # If dirty, show git status -sb (gs) and prompt for explicit confirmation
    if [ "$is_dirty" = true ]; then
      printf "\n\033[1;33m⚠ Worktree has uncommitted changes:\033[0m \033[1m%s\033[0m \033[2m[%s]\033[0m\n" "$wt_path" "$wt_branch"
      printf "\033[2m───────────────── Output of gs (git status -sb) ─────────────────\033[0m\n"
      git -C "$wt_path" status -sb
      printf "\033[2m─────────────────────────────────────────────────────────────────\033[0m\n"

      if [ "$force" = false ]; then
        printf "\033[1;31mDiscard uncommitted changes and delete this worktree?\033[0m [y/N]: "
        local confirm_dirty
        read -r confirm_dirty
        case "$confirm_dirty" in
          [yY]|[yY][eE][sS]) ;;
          *)
            printf "  \033[33mSkipping dirty worktree:\033[0m %s\n" "$wt_path"
            continue
            ;;
        esac
      fi
    fi

    printf "  Removing worktree \033[1m%s\033[0m..." "$wt_path"
    local rm_opts=()
    [ "$is_dirty" = true ] && rm_opts+=("--force")
    [ "$force" = true ] && rm_opts+=("--force")

    if git worktree remove "${rm_opts[@]}" "$wt_path" 2>/dev/null; then
      printf " \033[32m✔\033[0m\n"
      if [ -n "$wt_branch" ]; then
        if git branch -d "$wt_branch" 2>/dev/null; then
          printf "    Deleted local branch \033[2m%s\033[0m\n" "$wt_branch"
        else
          printf "    \033[33mNotice:\033[0m Local branch %s has unmerged commits; kept.\n" "$wt_branch"
        fi
      fi
    else
      printf " \033[31m✖ failed\033[0m\n"
    fi
  done

  git worktree prune
  printf "\033[32m✔ Worktree pruning complete!\033[0m\n"
}

# Git Local Merged Branch Cleaner (gbclean)
# Safely deletes local branches that are already merged into develop or main
gbclean() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi

  local base="main"
  if git show-ref --verify --quiet refs/heads/develop || git show-ref --verify --quiet refs/remotes/origin/develop; then
    base="develop"
  elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
    base="master"
  fi

  # Active worktree branches should never be deleted
  local active_branches
  active_branches=$(git worktree list 2>/dev/null | awk '{print $3}' | tr -d '[]')

  local merged_branches=()
  while IFS= read -r b; do
    local b_clean="$(echo "$b" | sed 's/^[ *+]*//')"
    [[ -z "$b_clean" ]] && continue
    # Protect main, master, develop, qa, stage, staging
    [[ "$b_clean" =~ ^(main|master|develop|qa|stage|staging|HEAD)$ ]] && continue
    # Protect branches checked out in any active worktree
    if echo "$active_branches" | grep -qx "$b_clean"; then
      continue
    fi
    merged_branches+=("$b_clean")
  done < <(git branch --merged "$base" 2>/dev/null)

  if [ "${#merged_branches[@]}" -eq 0 ]; then
    printf "\033[32m✔ No merged local branches to clean (compared to %s).\033[0m\n" "$base"
    return 0
  fi

  local selected_branches=()
  if command -v fzf &>/dev/null && [ -t 1 ]; then
    local fzf_output
    fzf_output=$(printf "%s\n" "${merged_branches[@]}" | fzf \
      --multi \
      --height=~45% \
      --layout=reverse \
      --border=rounded \
      --disabled \
      --pointer="❯ " \
      --marker="✔ " \
      --prompt="🗑 Select Merged Branches to Delete > " \
      --header="  j/k: navigate │ space/tab: toggle │ a: toggle all │ /: search │ enter: delete │ q: abort" \
      --color="header:italic:dim,prompt:bold:red,pointer:bold:red,marker:bold:green" \
      --bind="j:down,k:up,g:first,G:last,space:toggle+down,tab:toggle+down,btab:toggle+up,a:toggle-all,q:abort,ctrl-c:abort,enter:accept" \
      --bind="/:clear-query+enable-search+unbind(j,k,q,g,G,space,a,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ tab: toggle │ esc: normal mode │ enter: delete)+rebind(esc)" \
      --bind="i:enable-search+unbind(j,k,q,g,G,space,a,i,/)+change-prompt(🔍 Search > )+change-header(  type to filter │ tab: toggle │ esc: normal mode │ enter: delete)+rebind(esc)" \
      --bind="esc:disable-search+rebind(j,k,q,g,G,space,a,i,/)+change-prompt(🗑 Select Merged Branches to Delete > )+change-header(  j/k: navigate │ space/tab: toggle │ a: toggle all │ /: search │ enter: delete │ q: abort)+unbind(esc)" \
      --bind="start:unbind(esc)" \
      --preview='git log -n 10 --oneline --color=always {} 2>/dev/null' \
      --preview-window='right:55%:wrap')

    if [ -z "$fzf_output" ]; then
      printf "No branches selected. Aborted.\n"
      return 0
    fi

    while IFS= read -r b || [ -n "$b" ]; do
      selected_branches+=("$b")
    done <<< "$fzf_output"
  else
    printf "\n\033[1;33mFound %d local branch(es) merged into %s:\033[0m\n" "${#merged_branches[@]}" "$base"
    local b
    for b in "${merged_branches[@]}"; do
      printf "  • %s\n" "$b"
    done

    printf "\nDelete these merged branches? [Y/n]: "
    local confirm
    read -r confirm
    case "$confirm" in
      [nN]|[nN][oO])
        printf "Aborted. No branches deleted.\n"
        return 0
        ;;
      *)
        selected_branches=("${merged_branches[@]}")
        ;;
    esac
  fi

  local count=0
  for b in "${selected_branches[@]}"; do
    if git branch -d "$b" 2>/dev/null; then
      printf "  \033[32m✔\033[0m Deleted %s\n" "$b"
      ((count++))
    else
      printf "  \033[31m✖\033[0m Could not delete %s\n" "$b"
    fi
  done
  printf "\033[32m✔ Cleaned %d merged branch(es)!\033[0m\n" "$count"
}

# Tab completion for wt: list active worktree names
_wt() {
  local -a wts
  while IFS= read -r line; do
    local p="$(echo "$line" | awk '{print $1}')"
    local b="$(basename "$p")"
    [[ "$b" != ".bare" && "$b" != ".git" ]] && wts+=("$b")
  done < <(git worktree list 2>/dev/null)
  _describe 'worktree' wts
}
(( $+functions[compdef] )) && compdef _wt wt

# Tab completion for gwtnew: list available remote branches
_gwtnew() {
  local -a branches
  while IFS= read -r b; do
    local b_clean="${b#origin/}"
    [[ "$b_clean" != "HEAD"* ]] && branches+=("$b_clean")
  done < <(git branch -r 2>/dev/null | sed 's/^[ *]*//')
  _describe 'remote branch' branches
}
(( $+functions[compdef] )) && compdef _gwtnew gwtnew gwtn

# Tab completion for gwtdel: list disposable worktrees
_gwtdel() {
  local -a wts
  local active_wt="$(git rev-parse --show-toplevel 2>/dev/null)"
  while IFS= read -r line; do
    local p="$(echo "$line" | awk '{print $1}')"
    local b="$(basename "$p")"
    local br="$(echo "$line" | awk '{print $3}' | tr -d '[]')"
    [[ "$b" == ".bare" || "$b" == ".git" || "$p" == "$active_wt" ]] && continue
    [[ "$br" =~ ^(main|master|develop|qa|stage|staging)$ ]] && continue
    wts+=("$b")
  done < <(git worktree list 2>/dev/null)
  _describe 'worktree to delete' wts
}
(( $+functions[compdef] )) && compdef _gwtdel gwtdel
