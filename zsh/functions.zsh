# Interactive shell functions loader
# Loads modular function suites from ~/.dotfiles/zsh/functions/*.zsh

ZSH_FUNCTIONS_DIR="${0:A:h}/functions"

# Canonical registry of all user-facing custom dotfiles shell functions
# Consumed by 'fa' (search.zsh) and the deep runtime test suite (cli/test.py)
typeset -ga DOTFILES_FUNCTIONS=(
  take d up tree lt groot gmain
  conf dotbranch clone
  port fkill fcon fssh
  wt gwtnew gwtenv gwts gwtdel gwtclean
  gbclean gstash ga gfile gl gco gsearch
  y copy clippaste scratch extract pack
  npmr bunr pnpmr
  fa fenv cheath
  toggle-autols toggle-autonotify notify strdiff
)

# ==========================================
# Shared Internal Helpers for Function Suites
# ==========================================

# Populates caller's `fzf_mode_flags` array with the modal-Vim FZF state machine,
# layout, border, pointer, prompt, header, and preview page-scroll bindings.
# Usage: _fzf_vim_mode <prompt> <header> <enter_action> [extra_keys] [initial_query] [extra_binds]
_fzf_vim_mode() {
  local normal_prompt="$1"
  local normal_header="$2"
  local enter_action="${3:-select}"
  local extra_keys="$4"
  local initial_query="$5"
  local extra_binds="$6"

  local key_list="j,k,q,g,G"
  [ -n "$extra_keys" ] && key_list="${key_list},${extra_keys}"
  key_list="${key_list},i,/"

  local base_binds="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort,enter:accept"
  [ -n "$extra_binds" ] && base_binds="${base_binds},${extra_binds}"

  local search_header="  type to filter │ esc: normal mode │ enter: ${enter_action}"
  local to_search="enable-search+unbind(${key_list})+change-prompt(🔍 Search > )+change-header(${search_header})+rebind(esc)"
  local to_normal="disable-search+rebind(${key_list})+change-prompt(${normal_prompt})+change-header(${normal_header})+unbind(esc)"

  fzf_mode_flags=(
    "--layout=reverse"
    "--border=rounded"
    "--pointer=❯ "
    "--prompt=${normal_prompt}"
    "--header=${normal_header}"
    "--bind=ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up"
  )

  if [ -z "$initial_query" ]; then
    fzf_mode_flags+=(
      "--disabled"
      "--bind=start:unbind(esc)"
      "--bind=${base_binds}"
      "--bind=/:clear-query+${to_search}"
      "--bind=i:${to_search}"
      "--bind=esc:${to_normal}"
    )
  else
    fzf_mode_flags+=("--query=${initial_query}")
    [ -n "$extra_binds" ] && fzf_mode_flags+=("--bind=${extra_binds}")
  fi
}

# Verify current directory is inside a Git working tree
_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf "\033[31m✖ Not inside a git repository or worktree.\033[0m\n" >&2
    return 1
  fi
}

# Resolve the primary repository root directory (even when inside a linked git worktree)
_git_main_root() {
  local common_dir
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -n "$common_dir" ]; then
    (cd "$common_dir/.." && pwd)
  else
    git rev-parse --show-toplevel 2>/dev/null
  fi
}

# Detect default base branch for the current repository (develop -> master -> main)
_git_base_branch() {
  if git show-ref --verify --quiet refs/heads/develop || git show-ref --verify --quiet refs/remotes/origin/develop; then
    echo "develop"
  elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "master"
  else
    echo "main"
  fi
}

# Open a file in $EDITOR (with nano fallback), jumping to +line when supported
_edit_file() {
  local file="$1"
  local line="$2"
  local editor="${EDITOR:-nvim}"
  command -v "$editor" &>/dev/null || editor="nano"
  if [ -n "$line" ] && [[ "$editor" == *vim* ]]; then
    "$editor" "+$line" "$file"
  else
    "$editor" "$file"
  fi
}

# Copy a string to clipboard via copy() with confirmation message, or print to stdout
_copy_or_print() {
  local val="$1"
  local label="${2:-to clipboard}"
  if (( $+functions[copy] )); then
    printf "%s" "$val" | copy
    printf "\033[32m✔ Copied %s\033[0m\n" "$label"
  else
    printf "%s\n" "$val"
  fi
}

if [ -d "$ZSH_FUNCTIONS_DIR" ]; then
  # Temporarily disable alias expansion while loading function definitions
  # so active aliases never corrupt function declarations on reload/re-source
  local _aliases_were_active=false
  [[ -o aliases ]] && _aliases_were_active=true
  setopt NO_ALIASES

  for _func_file in "$ZSH_FUNCTIONS_DIR"/*.zsh(N); do
    source "$_func_file"
  done
  unset _func_file

  [ "$_aliases_were_active" = true ] && setopt ALIASES
  unset _aliases_were_active
fi
