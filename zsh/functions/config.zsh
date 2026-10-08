# Dynamic Configuration Manager (fuzzy matching & auto-reloading)
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

  # 2. Dynamic discovery in ~/.dotfiles/config and ~/.config
  local search_dir
  for search_dir in "$dot_dir/config" "$cfg_dir"; do
    [ -d "$search_dir" ] || continue
    for item in "$search_dir"/*(N); do
      local bname="$(basename "$item")"
      [[ "$bname" == .* ]] && continue

      if [ -d "$item" ]; then
        local primary=""
        for sub in "$item"/config*(N) "$item"/spaceship.zsh(N) "$item"/settings.json(N) "$item"/theme.yml(N) "$item"/init.lua(N) "$item"/.gitconfig(N); do
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
  done

  # 3. Modular dotfiles functions
  if [ -d "$dot_dir/zsh/functions" ]; then
    for mod in "$dot_dir/zsh/functions"/*.zsh(N); do
      local mname="$(basename "$mod" .zsh)"
      printf "%s\t%s\n" "$mname" "$mod"
    done
  fi
}

conf() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mconf\033[0m — Fuzzy configuration opener with auto-reload (macOS & Linux)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  conf                  Interactive modal-Vim FZF browser of all configurations\n"
    printf "  conf <target>         Open matching config (e.g. conf zsh, conf nvim, conf ghostty)\n"
    printf "  conf <path>           Open file or directory path directly\n"
    return 0
  fi

  local target_file=""
  local is_shell_rc=false

  # 1. If nothing passed and not in an interactive FZF-capable terminal, default to ~/.zshrc
  if [ -z "$1" ] && { [ ! -t 1 ] || ! command -v fzf &>/dev/null; }; then
    target_file="$HOME/.zshrc"
    is_shell_rc=true
  # 2. If an explicit file or directory path was given
  elif [ -n "$1" ] && { [ -f "$1" ] || [ -d "$1" ]; }; then
    target_file="$1"
  else
    local query="$1"
    local all_candidates
    all_candidates=$(_conf_candidates)

    # Check for exact key match first (case-insensitive) when a query is provided
    local exact_match=""
    if [ -n "$query" ]; then
      exact_match=$(echo "$all_candidates" | awk -F'\t' -v q="$query" 'tolower($1) == tolower(q) { print $2; exit }')
    fi

    if [ -n "$exact_match" ]; then
      target_file="$exact_match"
    else
      # Fuzzy filter candidate entries (or deduplicate by path when browsing all)
      local matches=""
      local match_count=0
      if [ -n "$query" ]; then
        matches=$(echo "$all_candidates" | awk -F'\t' -v q="$query" 'tolower($1) ~ tolower(q) || tolower($2) ~ tolower(q) { if (!seen[$2]++) print $0 }')
        match_count=$(echo "$matches" | grep -c . || true)
      fi

      if [ "$match_count" -eq 1 ]; then
        target_file=$(echo "$matches" | awk -F'\t' '{print $2}')
      elif command -v fzf &>/dev/null; then
        local candidate_pool="$matches"
        [ -z "$candidate_pool" ] && candidate_pool=$(echo "$all_candidates" | awk -F'\t' '!seen[$2]++ { print $0 }')

        local -a fzf_mode_flags
        _fzf_vim_mode "⚙  Edit Config > " "  j/k: navigate │ /: search │ enter: open │ q: quit" "open" "" "$query"

        local selected
        selected=$(echo "$candidate_pool" | awk -F'\t' '{ printf "%-16s │ %s\t%s\n", $1, $2, $2 }' | fzf \
          --delimiter='\t' \
          --with-nth=1 \
          --height=~50% \
          "${fzf_mode_flags[@]}" \
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
    *"/.zshrc"|*"/.aliases"|*"/zsh/functions.zsh"|*"/zsh/functions/"*|*"/spaceship.zsh")
      is_shell_rc=true
      ;;
  esac

  if [ -d "$target_file" ]; then
    _edit_file "$target_file"
    return 0
  fi

  [ ! -f "$target_file" ] && touch "$target_file"

  local before_sum
  before_sum=$(cksum "$target_file" 2>/dev/null)

  _edit_file "$target_file"

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

# Dotfiles Branch Switcher (dotbranch / .branch / .b)
# Switch active ~/.dotfiles branch from anywhere and immediately reload the shell.
# Usage:
#   .branch              -> Interactive Vim-modal FZF branch picker for ~/.dotfiles
#   .branch -            -> Toggle back to previous dotfiles branch (e.g. main <-> testing)
#   .branch <name>       -> Switch to matching dotfiles branch (e.g. .branch main, .branch async)
#   .branch -b <new>     -> Create and switch to a new dotfiles branch
#   .branch -s           -> Show current active dotfiles branch & status
dotbranch() {
  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
  if [ ! -d "$dot_dir/.git" ] && ! git -C "$dot_dir" rev-parse --git-dir &>/dev/null; then
    printf "\033[31m✖ Dotfiles git repository not found at %s\033[0m\n" "$dot_dir" >&2
    return 1
  fi

  local current_branch
  current_branch=$(git -C "$dot_dir" branch --show-current 2>/dev/null)

  case "$1" in
    -h|--help)
      printf "\033[1;38;2;203;166;247mdotbranch\033[0m (aliases: \033[1m.branch\033[0m, \033[1m.b\033[0m) — Switch active ~/.dotfiles branch & reload shell\n\n"
      printf "  Current branch: \033[1;38;2;166;227;161m%s\033[0m\n\n" "${current_branch:-detached}"
      printf "\033[1mUsage:\033[0m\n"
      printf "  .branch              Interactive Vim-modal branch selector\n"
      printf "  .branch -            Toggle between current and previous branch (e.g. stable <-> testing)\n"
      printf "  .branch <query>      Switch to matching branch (e.g. .branch main, .branch async)\n"
      printf "  .branch -b <name>    Create & switch to a new dotfiles branch\n"
      printf "  .branch -s           Show current dotfiles branch and status\n"
      return 0
      ;;
    -s|--status)
      printf "\033[1;38;2;203;166;247m⚙ Dotfiles (%s)\033[0m on \033[1;38;2;166;227;161m %s\033[0m\n" "$dot_dir" "${current_branch:-detached}"
      git -C "$dot_dir" status -sb
      return 0
      ;;
    -b|--create)
      if [ -z "$2" ]; then
        printf "\033[33mUsage: .branch -b <new-branch-name>\033[0m\n" >&2
        return 1
      fi
      if git -C "$dot_dir" checkout -b "$2"; then
        _dotbranch_reload "$dot_dir" "$2"
        return 0
      fi
      return 1
      ;;
  esac

  local target="$1"

  # Toggle to previous branch with `.branch -`
  if [ "$target" = "-" ]; then
    if git -C "$dot_dir" checkout -; then
      local new_br
      new_br=$(git -C "$dot_dir" branch --show-current 2>/dev/null)
      _dotbranch_reload "$dot_dir" "$new_br"
      return 0
    fi
    return 1
  fi

  # Collect local and remote branches (deduplicated, excluding current branch & HEAD)
  local branches=()
  local b
  while IFS= read -r b; do
    [[ -z "$b" || "$b" == "$current_branch" || "$b" == dura/* ]] && continue
    branches+=("$b")
  done < <(
    {
      git -C "$dot_dir" for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ 2>/dev/null
      git -C "$dot_dir" for-each-ref --sort=-committerdate --format='%(refname:lstrip=3)' refs/remotes/origin/ 2>/dev/null | grep -v '^HEAD$'
    } | awk '!seen[$0]++'
  )

  if [ -n "$target" ]; then
    # Exact match check first
    if git -C "$dot_dir" show-ref --verify --quiet "refs/heads/$target" || \
       git -C "$dot_dir" show-ref --verify --quiet "refs/remotes/origin/$target"; then
      if git -C "$dot_dir" checkout "$target"; then
        _dotbranch_reload "$dot_dir" "$target"
        return 0
      fi
      return 1
    fi

    # Fuzzy match against branch list
    local matched
    matched=$(printf "%s\n" "${branches[@]}" | grep -i "$target" | head -n 1)
    if [ -n "$matched" ]; then
      if git -C "$dot_dir" checkout "$matched"; then
        _dotbranch_reload "$dot_dir" "$matched"
        return 0
      fi
      return 1
    else
      printf "\033[31m✖ No dotfiles branch matching '%s'. Use '.branch -b %s' to create it.\033[0m\n" "$target" "$target" >&2
      return 1
    fi
  fi

  if [ "${#branches[@]}" -eq 0 ]; then
    printf "\033[33mOnly one branch ('%s') exists in ~/.dotfiles. Use '.branch -b <name>' to create one.\033[0m\n" "$current_branch"
    return 0
  fi

  if ! command -v fzf &>/dev/null; then
    printf "Current dotfiles branch: %s\nAvailable branches:\n" "$current_branch"
    printf "  %s\n" "${branches[@]}"
    return 0
  fi

  local -a fzf_mode_flags
  _fzf_vim_mode "⚙ Dotfiles Branch [current: ${current_branch}] > " "  j/k: navigate │ /: search │ enter: switch & reload │ q: quit" "switch & reload"

  target=$(printf "%s\n" "${branches[@]}" | fzf \
    --height=~45% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:green" \
    --preview="git -C '$dot_dir' log -n 12 --oneline --graph --decorate --color=always {} 2>/dev/null" \
    --preview-window='right:55%:wrap')

  if [ -n "$target" ]; then
    if git -C "$dot_dir" checkout "$target"; then
      _dotbranch_reload "$dot_dir" "$target"
    fi
  fi
}

_dotbranch_reload() {
  local dot_dir="$1"
  local branch_name="$2"

  # Auto-heal symlinks for the target branch's directory layout
  if [ -x "$dot_dir/bin/dot" ]; then
    "$dot_dir/bin/dot" doctor --fix >/dev/null 2>&1 || true
  fi

  # Cleanly tear down Spaceship prompt hooks before re-sourcing ~/.zshrc
  autoload -Uz add-zsh-hook
  (( $+functions[async_stop_worker] )) && async_stop_worker "spaceship" "spaceship_1" "spaceship_2" "spaceship_3" 2>/dev/null || true
  add-zsh-hook -d precmd prompt_spaceship_precmd 2>/dev/null || true
  add-zsh-hook -d preexec prompt_spaceship_preexec 2>/dev/null || true
  add-zsh-hook -d chpwd prompt_spaceship_chpwd 2>/dev/null || true
  RPROMPT=""
  [[ -t 1 && ! -t 2 ]] && exec 2>&1

  ZSH_STARTUP_VERBOSE=false source "$HOME/.zshrc"
  printf "\033[1;32m✔\033[0m Active dotfiles branch switched to \033[1;38;2;203;166;247m%s\033[0m and shell reloaded!\n" "$branch_name"
}

# Tab completion for dot CLI: subcommands and per-command flags
_dot() {
  local -a subcommands flags
  if (( CURRENT == 2 )); then
    subcommands=(
      'status:Quick overview of dotfiles, symlinks, and runtimes'
      'doctor:System & environment health check (--fix to repair symlinks)'
      'test:Deep integration, parser & shell runtime test suite'
      'bench:Profile interactive Zsh startup latency by phase'
      'clean:Prune stale completion dumps, caches & old scratch files'
      'prune:Remove links, caches & packages deleted from the dotfiles'
      'update:Sync dotfiles repo & upgrade Brew / Mise tools'
      'link:Verify and heal all declarative configuration symlinks'
    )
    _describe 'dot command' subcommands
  else
    case "${words[2]}" in
      doctor|link)
        flags=('--fix:Auto-repair broken or missing symlinks' '-f:Auto-repair broken or missing symlinks')
        ;;
      bench)
        flags=('-n:Number of benchmark iterations' '--iterations:Number of benchmark iterations')
        ;;
      clean)
        flags=(
          '-n:Preview files to remove without deleting'
          '--dry-run:Preview files to remove without deleting'
          '-a:Also prune old scratch notes (>30 days)'
          '--all:Also prune old scratch notes (>30 days)'
        )
        ;;
      prune)
        flags=(
          '-n:Preview what would be removed without deleting'
          '--dry-run:Preview what would be removed without deleting'
          '-o:Also offer to uninstall packages the dotfiles do not declare'
          '--orphans:Also offer to uninstall packages the dotfiles do not declare'
        )
        ;;
      update)
        flags=(
          '-c:Check for upstream updates without applying'
          '--check:Check for upstream updates without applying'
          '-a:Upgrade all packages without prompting'
          '--all:Upgrade all packages without prompting'
          '--no-prune:Keep links, caches & packages removed upstream'
        )
        ;;
    esac
    (( ${#flags[@]} )) && _describe 'flag' flags
  fi
}
(( $+functions[compdef] )) && compdef _dot dot

# Tab completion for conf: list available configuration targets
_conf() {
  local -a targets
  while IFS=$'\t' read -r k p; do
    [ -n "$k" ] && targets+=("${k}:${p/$HOME/~}")
  done < <(_conf_candidates 2>/dev/null | awk -F'\t' '!seen[$1]++')
  _describe 'config target' targets
}
(( $+functions[compdef] )) && compdef _conf conf

