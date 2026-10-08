# Git & Worktree Helpers

# Smart Git Clone: supports full URLs, owner/repo shorthand, auto-cd, and -b/--bare worktree hub setup
clone() {
  local bare_mode=false
  local repo=""
  local target_dir=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        printf "Usage: clone [-b|--bare] <url|owner/repo|repo> [directory]\n"
        printf "  clone owner/repo         Clone git@github.com:owner/repo.git and cd into it\n"
        printf "  clone my-repo            Clone git@github.com:JoshQuaintance/my-repo.git and cd into it\n"
        printf "  clone -b owner/repo      Clone as a .bare worktree hub and cd into its default branch worktree\n"
        return 0
        ;;
      -b|--bare)
        bare_mode=true
        ;;
      *)
        if [ -z "$repo" ]; then
          repo="$arg"
        elif [ -z "$target_dir" ]; then
          target_dir="$arg"
        fi
        ;;
    esac
  done

  if [ -z "$repo" ]; then
    printf "Usage: clone [-b|--bare] <url|owner/repo|repo> [directory]\n" >&2
    return 1
  fi

  local clone_url=""
  case "$repo" in
    http://*|https://*|git@*|ssh://*|file://*)
      clone_url="$repo"
      ;;
    */*)
      clone_url="git@github.com:${repo%.git}.git"
      ;;
    *)
      local gh_user
      gh_user="$(git config --get github.user 2>/dev/null || echo "JoshQuaintance")"
      clone_url="git@github.com:${gh_user}/${repo%.git}.git"
      ;;
  esac

  if [ -z "$target_dir" ]; then
    target_dir="$(basename "${clone_url%.git}")"
  fi

  if [ "$bare_mode" = true ]; then
    printf "\033[1;34m==>\033[0m Cloning bare worktree hub \033[1m%s\033[0m into \033[1;36m%s\033[0m...\n" "$clone_url" "$target_dir"
    mkdir -p "$target_dir" || return 1
    if ! git clone --bare "$clone_url" "$target_dir/.bare"; then
      rmdir "$target_dir" 2>/dev/null || true
      return 1
    fi
    echo "gitdir: ./.bare" > "$target_dir/.git"
    git -C "$target_dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git -C "$target_dir" fetch origin --quiet 2>/dev/null || true

    local def_branch
    def_branch="$(git -C "$target_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||')"
    if [ -z "$def_branch" ]; then
      if git -C "$target_dir" show-ref --verify --quiet refs/remotes/origin/develop; then
        def_branch="develop"
      elif git -C "$target_dir" show-ref --verify --quiet refs/remotes/origin/main; then
        def_branch="main"
      else
        def_branch="master"
      fi
    fi

    git -C "$target_dir" worktree add "$target_dir/$def_branch" "$def_branch" || return 1
    printf "\033[32m✔ Bare worktree hub ready! Switching to %s/%s\033[0m\n" "$target_dir" "$def_branch"
    cd "$target_dir/$def_branch"
  else
    printf "\033[1;34m==>\033[0m Cloning \033[1m%s\033[0m into \033[1;36m%s\033[0m...\n" "$clone_url" "$target_dir"
    if git clone "$clone_url" "$target_dir"; then
      cd "$target_dir"
    else
      return 1
    fi
  fi
}

gsearch() {
  git log --all --grep="$1" --oneline
}

# Interactive Git Graph & Diff Browser (gl)
# Browses the commit graph interactively with live side-by-side diff previews.
# Supports Enter (pager diff), Ctrl-V (Neovim Diffview), Ctrl-Y (copy hash), and Tab (range diff).
gl() {
  _require_git_repo || return 1

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

  local -a fzf_mode_flags
  _fzf_vim_mode "📜 Git Graph > " "j/k: move • /: search • Enter: diff • Ctrl-V: nvim diffview • Ctrl-Y: copy hash • q: quit" "diff"

  local selection
  selection=$(eval "$git_log_cmd" | fzf \
    --ansi \
    --multi \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    --preview="$preview_cmd" \
    --preview-window="right:60%:wrap" \
    --expect="ctrl-v,ctrl-y") || return 0

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
      _copy_or_print "$joined_hashes" "hash(es) to clipboard: $joined_hashes"
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

  local -a fzf_mode_flags
  _fzf_vim_mode "🌿 Checkout Branch > " "  j/k: navigate │ /: search │ enter: checkout │ q: quit" "checkout"

  local target
  target=$(printf "%s\n" "${branches[@]}" | fzf \
    --height=~45% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:cyan" \
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
  _require_git_repo || return 1

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

  local -a fzf_mode_flags
  _fzf_vim_mode "📦 Git Stashes > " "  j/k: navigate │ /: search │ enter: apply │ p: pop │ space+x: drop │ q: quit" "apply" "space,p,x" "" "space:toggle+down"

  local selection
  selection=$(printf "%s\n" "$stashes" | fzf \
    --ansi \
    --multi \
    --height=~50% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:cyan,marker:bold:red" \
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

  _require_git_repo || return 1

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

  local -a fzf_mode_flags
  _fzf_vim_mode "📂 Git Stage/Unstage > " "  j/k: move │ space: select │ enter: stage │ u: unstage │ x: discard │ e: edit │ /: search │ q: quit" "stage" "space,u,x,e" "" "space:toggle+down"

  local selection
  selection=$(printf "%s\n" "$status_lines" | fzf \
    --ansi \
    --multi \
    --height=~55% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:green,pointer:bold:cyan,marker:bold:yellow" \
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

# Interactive Single-File Git History & Time-Travel (gfile / gfh)
# Usage:
#   gfile <file>       -> Browse commit history for <file> with file-scoped delta diff preview
#   gfile              -> Pick a tracked file via FZF first, then browse its commit history
#   Keys: enter = view diff, ctrl-v = nvim DiffviewFileHistory, r = restore file from commit, y = copy SHA
gfile() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mgfile\033[0m (alias: \033[1mgfh\033[0m) — Interactive single-file Git commit history & time-travel\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  gfile <path>       Browse commits that touched <path> with file-scoped delta preview\n"
    printf "  gfile              Pick a tracked file interactively first, then browse its history\n"
    printf "  Enter              View full commit diff for this file\n"
    printf "  Ctrl-V             Open in Neovim DiffviewFileHistory\n"
    printf "  r                  Restore file contents from selected commit (with confirmation)\n"
    printf "  y                  Copy commit SHA to clipboard\n"
    return 0
  fi

  _require_git_repo || return 1

  local target_file="$1"

  # If no file argument provided, let user pick a tracked file via modal-Vim FZF
  if [ -z "$target_file" ]; then
    if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
      printf "\033[33mUsage: gfile <path>\033[0m\n" >&2
      return 1
    fi

    local -a fzf_mode_flags
    _fzf_vim_mode "📄 Select File for History > " "  j/k: navigate │ /: search │ enter: view git history │ q: quit" "select"

    target_file=$(git ls-files 2>/dev/null | fzf \
      --height=~55% \
      "${fzf_mode_flags[@]}" \
      --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
      --preview='if command -v bat &>/dev/null; then bat --color=always --style=numbers --line-range :250 {} 2>/dev/null; else head -n 200 {} 2>/dev/null; fi' \
      --preview-window='right:55%:wrap')

    [ -z "$target_file" ] && return 0
  fi

  local commits
  commits=$(git log --follow --color=always --format='%C(auto)%h%d %s %C(dim white)(%cr) %C(dim cyan)<%an>%Creset' -- "$target_file" 2>/dev/null)
  if [ -z "$commits" ]; then
    printf "\033[33mNo git commit history found for '%s'.\033[0m\n" "$target_file"
    return 1
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "%s\n" "$commits"
    return 0
  fi

  local hdr="  j/k: move │ /: search │ enter: diff │ ctrl-v: nvim diffview │ r: restore file │ y: copy SHA │ q: quit"
  local preview_cmd="
    h=\$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}')
    if [ -n \"\$h\" ]; then
      if command -v delta &>/dev/null; then
        git show --stat -p \"\$h\" -- '$target_file' 2>/dev/null | delta --paging=never --width=\"\${FZF_PREVIEW_COLUMNS:-80}\"
      else
        git show --color=always --stat -p \"\$h\" -- '$target_file' 2>/dev/null
      fi
    fi
  "

  local -a fzf_mode_flags
  _fzf_vim_mode "🕰  History ($target_file) > " "$hdr" "diff" "r,y"

  local selection
  selection=$(printf "%s\n" "$commits" | fzf \
    --ansi \
    --height=~65% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:green" \
    --preview="$preview_cmd" \
    --preview-window="right:60%:wrap" \
    --expect="ctrl-v,r,y")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_line
  selected_line=$(echo "$selection" | sed '1d' | head -n1)
  [ -z "$selected_line" ] && return 0

  local sha
  sha=$(printf "%s" "$selected_line" | sed $'s/\x1b\\[[0-9;]*m//g' | awk '{print $1}')
  [ -z "$sha" ] && return 0

  case "$key" in
    y)
      _copy_or_print "$sha" "commit SHA to clipboard: $sha"
      ;;
    ctrl-v)
      if command -v nvim &>/dev/null; then
        nvim -c "DiffviewFileHistory $target_file"
      else
        printf "\033[31m✖ Neovim (nvim) is not installed.\033[0m\n" >&2
      fi
      ;;
    r)
      printf "\033[1;33m⚠ Restore '%s' to state from commit %s? [y/N]: \033[0m" "$target_file" "$sha"
      local confirm=""
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        git checkout "$sha" -- "$target_file"
        printf "\033[32m✔ Restored '%s' from commit %s.\033[0m\n" "$target_file" "$sha"
        git status -sb -- "$target_file"
      else
        printf "\033[2mCancelled.\033[0m\n"
      fi
      ;;
    *)
      git show --stat -p "$sha" -- "$target_file"
      ;;
  esac
}


# Git Local Merged Branch Cleaner (gbclean)
# Safely deletes local branches that are already merged into develop or main
gbclean() {
  _require_git_repo || return 1

  local base
  base="$(_git_base_branch)"

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
    local -a fzf_mode_flags
    _fzf_vim_mode "🗑 Select Merged Branches to Delete > " "  j/k: navigate │ space/tab: toggle │ a: toggle all │ /: search │ enter: delete │ q: abort" "delete" "space,a" "" "space:toggle+down,tab:toggle+down,btab:toggle+up,a:toggle-all"

    local fzf_output
    fzf_output=$(printf "%s\n" "${merged_branches[@]}" | fzf \
      --multi \
      --height=~45% \
      --marker="✔ " \
      "${fzf_mode_flags[@]}" \
      --color="header:italic:dim,prompt:bold:red,pointer:bold:red,marker:bold:green" \
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

