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

  # 3. Modular dotfiles functions
  if [ -d "$dot_dir/zsh/functions" ]; then
    for mod in "$dot_dir/zsh/functions"/*.zsh(N); do
      local mname="$(basename "$mod" .zsh)"
      printf "%s\t%s\n" "$mname" "$mod"
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

        local fzf_mode_flags=()
        if [ -z "$query" ]; then
          fzf_mode_flags=(
            "--disabled"
            "--bind=j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept"
            "--bind=/:enable-search+unbind(j,k,q,g,G)+change-prompt(🔍 Search > )+change-header(  type to filter │ esc: normal mode │ enter: open)"
            "--bind=esc:disable-search+clear-query+rebind(j,k,q,g,G)+change-prompt(⚙  Edit Config > )+change-header(  j/k: navigate │ /: search │ enter: open │ q: quit)"
          )
        else
          fzf_mode_flags=("--query=$query")
        fi

        local selected
        selected=$(echo "$candidate_pool" | awk -F'\t' '{ printf "%-16s │ %s\t%s\n", $1, $2, $2 }' | fzf \
          --delimiter='\t' \
          --with-nth=1 \
          "${fzf_mode_flags[@]}" \
          --height=~50% \
          --layout=reverse \
          --border=rounded \
          --prompt="⚙  Edit Config > " \
          --header="  j/k: navigate │ /: search │ enter: open │ q: quit" \
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
    *"/.zshrc"|*"/.aliases"|*"/zsh/functions.zsh"|*"/zsh/functions/"*)
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
