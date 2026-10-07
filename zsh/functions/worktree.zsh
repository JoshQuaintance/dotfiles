# Shared helper to display git status -sb and prompt before deleting a dirty worktree
_confirm_dirty_worktree() {
  local wt_path="$1"
  local wt_branch="$2"
  local force="${3:-false}"
  printf "\n\033[1;33m⚠ Worktree has uncommitted changes:\033[0m \033[1m%s\033[0m \033[2m[%s]\033[0m\n" "$wt_path" "$wt_branch"
  printf "\033[2m───────────────── Output of gs (git status -sb) ─────────────────\033[0m\n"
  git -C "$wt_path" status -sb
  printf "\033[2m─────────────────────────────────────────────────────────────────\033[0m\n"
  [ "$force" = true ] && return 0
  printf "\033[1;31mDiscard uncommitted changes and delete this worktree?\033[0m [y/N]: "
  local confirm_dirty=""
  read -r confirm_dirty
  [[ "$confirm_dirty" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Git Worktree Interactive Switcher (wt)
# Dynamically queries git worktrees in the current repo and provides an interactive fzf selector
wt() {
  _require_git_repo || return 1

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
    local -a fzf_mode_flags
    _fzf_vim_mode "🌿 Worktree > " "  j/k: navigate │ /: search │ enter: cd │ q: quit" "cd" "" "$query"

    local selected
    selected=$(echo "$worktrees" | fzf \
      --height=~40% \
      "${fzf_mode_flags[@]}" \
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
  _require_git_repo || return 1

  local main_root base_branch
  main_root="$(_git_main_root)"
  base_branch="$(_git_base_branch)"

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

    local -a fzf_mode_flags
    _fzf_vim_mode "🌱 New Worktree from Branch > " "  j/k: navigate │ /: search / type new branch │ enter: select or create │ q: quit" "select or create"

    local fzf_raw
    fzf_raw=$(printf "%s\n" "${remote_branches[@]}" | fzf \
      --print-query \
      --height=~45% \
      "${fzf_mode_flags[@]}" \
      --color="header:italic:dim,prompt:bold:green,pointer:bold:green" \
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
  _require_git_repo || return 1

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
    wt_display_branch="$wt_branch"
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
  _require_git_repo || return 1

  local active_wt target_input="$1" target_wt="" target_branch=""
  local p b br bname item fzf_lines="" selected wt_name is_dirty=false
  local confirm_del confirm_br
  local -a eligible rm_opts
  active_wt="$(git rev-parse --show-toplevel 2>/dev/null)"

  # Collect eligible worktrees (exclude active worktree, bare repo, and protected branches)
  while IFS= read -r line; do
    p="$(echo "$line" | awk '{print $1}')"
    b="$(echo "$line" | awk '{print $3}' | tr -d '[]')"
    [[ "$b" == "(bare)" || -z "$b" ]] && continue
    [[ "$p" == "$active_wt" ]] && continue
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

    local -a fzf_mode_flags
    _fzf_vim_mode "🗑 Delete Worktree > " "  j/k: navigate │ /: search │ enter: select to delete │ q: quit" "select"

    selected=$(printf "%b" "$fzf_lines" | fzf \
      --delimiter=$'\t' \
      --with-nth=1,2 \
      --height=~40% \
      "${fzf_mode_flags[@]}" \
      --color="header:italic:dim,prompt:bold:red,pointer:bold:red" \
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

  wt_name="$(basename "$target_wt")"
  [ -n "$(git -C "$target_wt" status --porcelain 2>/dev/null)" ] && is_dirty=true

  if [ "$is_dirty" = true ]; then
    if ! _confirm_dirty_worktree "$target_wt" "$target_branch" false; then
      printf "Aborted. Worktree preserved.\n"
      return 0
    fi
  else
    printf "Delete worktree \033[1m%s\033[0m \033[2m[%s]\033[0m? [y/N]: " "$wt_name" "$target_branch"
    read -r confirm_del
    if [[ ! "$confirm_del" =~ ^[Yy]([Ee][Ss])?$ ]]; then
      printf "Aborted.\n"
      return 0
    fi
  fi

  [ "$is_dirty" = true ] && rm_opts+=("--force")

  printf "Removing worktree \033[1m%s\033[0m..." "$wt_name"
  if git worktree remove "${rm_opts[@]}" "$target_wt" 2>/dev/null; then
    printf " \033[32m✔\033[0m\n"
    if [ -n "$target_branch" ]; then
      printf "Delete local branch \033[1m%s\033[0m? [Y/n]: " "$target_branch"
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
  _require_git_repo || return 1

  local force=false
  if [[ "$1" == "-f" || "$1" == "--force" ]]; then
    force=true
  fi

  local main_worktree
  main_worktree="$(_git_main_root)"

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

    local -a fzf_mode_flags
    _fzf_vim_mode "🗑 Select Worktrees to Prune > " "  j/k: navigate │ space/tab: toggle │ a: toggle all │ /: search │ enter: confirm │ q: abort" "confirm" "space,a" "" "space:toggle+down,tab:toggle+down,btab:toggle+up,a:toggle-all"

    local fzf_output
    fzf_output=$(printf "%b" "$fzf_input" | fzf \
      --multi \
      --height=~45% \
      --marker="✔ " \
      "${fzf_mode_flags[@]}" \
      --color="header:italic:dim,prompt:bold:red,pointer:bold:red,marker:bold:green" \
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

    if [ "$is_dirty" = true ]; then
      if ! _confirm_dirty_worktree "$wt_path" "$wt_branch" "$force"; then
        printf "  \033[33mSkipping dirty worktree:\033[0m %s\n" "$wt_path"
        continue
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
