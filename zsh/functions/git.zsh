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

    target_input=$(printf "%s\n" "${remote_branches[@]}" | fzf \
      --height=~45% \
      --layout=reverse \
      --border=rounded \
      --prompt="🌱 New Worktree from Branch > " \
      --header="Enter: create worktree • Esc: cancel" \
      --color="header:italic:dim,prompt:bold:green,pointer:bold:green" \
      --preview='git log -n 10 --oneline --color=always "origin/{}" 2>/dev/null' \
      --preview-window='right:55%:wrap')

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
  elif [ "$count" -eq 1 ]; then
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
    # Multiple candidates: Interactive Multi-Select
    if command -v fzf &>/dev/null && [ -t 1 ]; then
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
        --prompt="🗑 Select Worktrees to Prune > " \
        --header="Tab: toggle selection • Alt-A: select all • Enter: confirm • Esc: cancel" \
        --color="header:italic:dim,prompt:bold:red,pointer:bold:green,marker:bold:green" \
        --preview='git -C {1} status -sb 2>/dev/null' \
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
    else
      # Fallback text multi-select menu
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
(( $+functions[compdef] )) && compdef _gwtnew gwtnew
