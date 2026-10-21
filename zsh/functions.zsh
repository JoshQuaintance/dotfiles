# ==============================================================================
# Interactive Shell Functions Loader & Shared Helpers (zsh/functions.zsh)
# ==============================================================================
# Loads modular function suites from ~/.dotfiles/zsh/functions/*.zsh and
# registers comma-prefixed (,<cmd>) shorthands via `zsh/functions/comma.zsh`.

ZSH_FUNCTIONS_DIR="${0:A:h}/functions"

# Canonical registry of all user-facing custom dotfiles shell functions.
# Consumed by `,` (comma.zsh), `fa` (search.zsh), and the deep runtime test suite (cli/test.py).
typeset -ga DOTFILES_FUNCTIONS=(
  # Comma Command Palette Launcher
  ,

  # Navigation, Directory Tree & WSL Path Bridge
  take d up tree lt groot gmain proj wpath wcd

  # Configuration & Repository Management
  conf dotbranch clone

  # System, Process, Network, Package & Diagnostic Tools
  port fkill fcon fssh dotenv fpkg decode fsize fknown termtest netinfo checksum hashc

  # Git Worktree Workflow
  wt gwtnew gwtenv gwts gwtdel gwtclean

  # Interactive Git Pickers
  gbclean gstash ga gfile gl gco gsearch

  # File Manager, Clipboard, Scratchpad & Archives
  y copy clippaste clip lastout scratch extract pack

  # Node / Bun / pnpm Script Runners
  npmr bunr pnpmr

  # Search, Environment, Cheat Sheets, Data Explorer & Snippets
  fa fenv cheath fjq snip

  # Shell Hooks & Diff Utilities
  toggle-autols toggle-autonotify notify strdiff
)

# ==========================================
# Shared Internal Helpers for Function Suites
# ==========================================

# Populates caller's `fzf_mode_flags` array with the modal-Vim FZF state machine,
# layout, border, pointer, prompt, header, and preview page-scroll bindings.
#
# Output Protocol:
#   - When `extra_keys` contains action keys (e.g. "e,y" or "ctrl-v,ctrl-y") that are not bound
#     to in-fzf actions in `extra_binds`, FZF is configured with `enter:print()+accept` and
#     `<key>:print(<key>)+accept`. FZF's stdout then consists of:
#       Line 1:     The pressed key name (empty string "" when Enter was pressed)
#       Lines 2..N: The selected item line(s)
#     Use `_fzf_split_expect "$selection"` in the caller to split Line 1 (`key`) from Lines 2..N (`selected_lines`).
#   - When no expect keys are present, `enter:accept` is used and stdout contains only the selected line(s).
#
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

  # Keys from extra_keys that are not bound to in-fzf actions (e.g. toggle) act as expect keys
  local -a expect_keys=()
  if [ -n "$extra_keys" ]; then
    local -a ek_list=(${(s:,:)extra_keys})
    for k in "${ek_list[@]}"; do
      if [ -n "$k" ] && [ "$k" != "space" ] && [[ ",${extra_binds}," != *",${k}:"* ]]; then
        expect_keys+=("$k")
      fi
    done
  fi

  local base_binds="j:down,k:up,g:first,G:last,q:abort,ctrl-c:abort"
  if (( ${#expect_keys[@]} > 0 )); then
    base_binds="${base_binds},enter:print()+accept"
    for ek in "${expect_keys[@]}"; do
      base_binds="${base_binds},${ek}:print(${ek})+accept"
    done
  else
    base_binds="${base_binds},enter:accept"
  fi
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
    fzf_mode_flags+=(
      "--query=${initial_query}"
      "--bind=start:unbind(${key_list})"
      "--bind=${base_binds}"
      "--bind=/:clear-query+${to_search}"
      "--bind=i:${to_search}"
      "--bind=esc:${to_normal}"
    )
  fi
}

# Pure-Zsh parser for `_fzf_vim_mode` expect-key output (0 subshell forks).
# Populates caller's `key` (line 1, empty on Enter) and `selected_lines` (lines 2..N).
# Returns 1 if selection was cancelled or no item lines were selected.
_fzf_split_expect() {
  local raw="$1"
  [[ "$raw" == *$'\n'* ]] || return 1
  key="${raw%%$'\n'*}"
  selected_lines="${raw#*$'\n'}"
  [[ -n "$selected_lines" ]]
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
    if printf "%s" "$val" | copy; then
      printf "\033[32m✔ Copied %s\033[0m\n" "$label"
    else
      printf "%s\n" "$val"
      return 1
    fi
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

  # Register all comma-prefixed (,<cmd>) wrapper functions defined in zsh/functions/comma.zsh
  (( $+functions[_comma_register_wrappers] )) && _comma_register_wrappers
fi
