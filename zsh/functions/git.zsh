# Git & Worktree Helpers

clone() {
  local repo=$1
  echo "Cloning $repo - git clone git@github.com:$repo.git"
  git clone "git@github.com:$repo.git"
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

# Git Worktree Clean (gwtclean / gwtc)
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

  printf "\n\033[1;33mFound %d worktree(s) whose remote tracking branch is gone:\033[0m\n" "$count"
  local item
  for item in "${candidates[@]}"; do
    local wt_path="${item%%|*}"
    local wt_branch="${item##*|}"
    local status_notes=""

    if [ "$PWD" = "$wt_path" ] || [[ "$PWD" == "$wt_path"/* ]]; then
      status_notes=" \033[33m(ACTIVE: currently inside)\033[0m"
    fi

    if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
      status_notes="${status_notes} \033[31m(DIRTY: uncommitted changes)\033[0m"
    fi

    printf "  \033[1;36m•\033[0m %-44s \033[2m[%s]\033[0m%b\n" "$wt_path" "$wt_branch" "$status_notes"
  done

  echo ""
  if [ "$force" = false ]; then
    printf "Remove these worktrees and delete local branches? [y/N]: "
    local confirm
    read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *)
        printf "Aborted. No worktrees were removed.\n"
        return 0
        ;;
    esac
  fi

  for item in "${candidates[@]}"; do
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

    if [ "$is_dirty" = true ] && [ "$force" = false ]; then
      printf "  \033[31m⚠ Skipping dirty worktree (uncommitted changes):\033[0m %s\n" "$wt_path"
      continue
    fi

    printf "  Removing worktree \033[1m%s\033[0m..." "$wt_path"
    local rm_opts=()
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
  printf "\033[32m✔ Worktree cleanup complete!\033[0m\n"
}
