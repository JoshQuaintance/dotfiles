# ==============================================================================
# Comma-Prefix Command System & Interactive Command Palette (zsh/functions/comma.zsh)
# ==============================================================================
# Implements the Unix `,` prefix convention ("Start all of your commands with a comma"):
#   - Every custom dotfiles function in $DOTFILES_FUNCTIONS gets a `,<name>` wrapper
#   - Ergonomic short names (e.g. `,net`, `,hash`, `,pkg`, `,kill`) map to their canonical tools
#   - Typing `,` + <Enter> opens an interactive modal-Vim FZF Command Palette
#   - Typing `, <Tab>` or `,<Tab>` completes all custom dotfiles commands

# Primary short `,` names for functions whose canonical name has an `f` prefix or longer form.
# Consumed by both `_comma_register_wrappers` and `_comma_gen_list` (single source of truth).
typeset -gA DOTFILES_COMMA_SHORTHANDS=(
  # System & Network Diagnostics
  netinfo           ,net
  checksum          ,hash
  fkill             ,kill
  fpkg              ,pkg
  fsize             ,size
  fssh              ,ssh
  fcon              ,con
  fknown            ,known

  # Search, Environment & Data Explorers
  fa                ,a
  fenv              ,env
  fjq               ,jq
  cheath            ,cheat

  # Configuration & Shell Toggles
  dotbranch         ,branch
  toggle-autols     ,autols
  toggle-autonotify ,autonotify
)

# Additional convenience `,` aliases that point to canonical functions or bin tools.
typeset -gA DOTFILES_COMMA_ALIASES=(
  ,brew             fpkg
  ,docker           fcon
  ,ports            port
  ,projects         proj
  ,snippets         snip
  ,dot              dot
)

# Register all `,<cmd>` wrapper functions from $DOTFILES_FUNCTIONS, $DOTFILES_COMMA_SHORTHANDS,
# and $DOTFILES_COMMA_ALIASES. Invoked automatically by `zsh/functions.zsh` after loading suites.
_comma_register_wrappers() {
  local fn short_comma alias_comma target_cmd

  for fn in "${DOTFILES_FUNCTIONS[@]}"; do
    [[ "$fn" == "," ]] && continue
    if (( $+functions[$fn] )); then
      functions[,$fn]="\"$fn\" \"\$@\""
      short_comma="${DOTFILES_COMMA_SHORTHANDS[$fn]:-}"
      if [[ -n "$short_comma" ]]; then
        functions[$short_comma]="\"$fn\" \"\$@\""
      fi
    fi
  done

  for alias_comma target_cmd in "${(@kv)DOTFILES_COMMA_ALIASES}"; do
    functions[$alias_comma]="\"$target_cmd\" \"\$@\""
  done
}

# Internal helper: generate tab-delimited catalog of comma-prefixed commands for `,`
# Output format: <,short>\t<canonical>\t<description>
_comma_gen_list() {
  local dot_dir="${1:-${DOTFILES_DIR:-$HOME/.dotfiles}}"
  local -A func_docs
  local k v

  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] && func_docs[$k]="$v"
  done < <(awk '
    /^#[[:space:]]+/ {
      line = $0
      sub(/^#[[:space:]]+/, "", line)
      if (line !~ /^(Usage:|===|---)/ && prev == "") prev = line
      next
    }
    /^(,|[A-Za-z0-9_-]+)\(\)[[:space:]]*\{/ {
      fn = $0
      sub(/\(\).*/, "", fn)
      if (prev != "") print fn "\t" prev
      prev = ""
      next
    }
    { prev = "" }
  ' "$dot_dir"/zsh/functions/*.zsh 2>/dev/null)

  local fn comma_name desc
  for fn in "${DOTFILES_FUNCTIONS[@]}"; do
    [[ "$fn" == "," ]] && continue
    if (( $+functions[$fn] )); then
      comma_name="${DOTFILES_COMMA_SHORTHANDS[$fn]:-,${fn}}"
      desc="${func_docs[$fn]:-(custom dotfiles function)}"
      printf "%s\t%s\t%s\n" "$comma_name" "$fn" "$desc"
    fi
  done

  if [[ -d "$dot_dir/bin" ]]; then
    local b bname bdesc
    for b in "$dot_dir/bin/"*(N); do
      if [[ -f "$b" && -x "$b" ]]; then
        bname="${b:t}"
        bdesc=$(awk '/^#[[:space:]]*Description:[[:space:]]*/ { sub(/^#[[:space:]]*Description:[[:space:]]*/, ""); print; exit } NR > 15 { exit }' "$b" 2>/dev/null)
        [[ "$bname" == "dot" && -z "$bdesc" ]] && bdesc="Unified developer workstation CLI (status, doctor, test, env, sync, backup)"
        printf ",%s\t%s\t%s\n" "$bname" "$bname" "${bdesc:-(CLI utility in ~/.dotfiles/bin)}"
      fi
    done
  fi
}

# Interactive Dotfiles Command Palette & Comma-Prefix Launcher (, / f)
# Usage:
#   ,                  -> Open modal-Vim FZF palette of all custom `,` commands
#   , <query>          -> Open palette pre-filtered by <query> (or run exact command if args follow)
#   , <cmd> <args...>  -> Execute custom command <cmd> directly with <args...>
#   , -l, --list       -> Print tab-separated table of all `,` commands
,() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;203;166;247m,\033[0m (alias: \033[1mf\033[0m) — Interactive Dotfiles Command Palette & comma-prefix launcher\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  ,                    Browse & launch all custom dotfiles commands in FZF\n"
    printf "  ,<cmd> [args...]     Run any comma-prefixed command directly (e.g. ,port, ,pkg, ,net, ,hash)\n"
    printf "  , <cmd> <args...>    Dispatch to <cmd> with arguments\n"
    printf "  , <query>            Open command palette filtered by <query>\n"
    printf "  , -l, --list [query] List all comma-prefixed commands and descriptions\n"
    printf "  Enter                Execute selected command (or insert on prompt if it requires a path/arg)\n"
    printf "  e                    Insert command onto Zsh prompt to add flags/arguments\n"
    printf "  h                    Show --help for the selected command\n"
    printf "  y                    Copy command name to clipboard\n"
    return 0
  fi

  local list_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  fi

  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"

  # Direct dispatch when called as `, <cmd> <args...>` (with 2+ tokens and a known command)
  if [[ "$list_only" == false ]] && (( $# >= 2 )); then
    local candidate="${1#,}"
    if (( $+functions[,$candidate] )); then
      shift
      ",$candidate" "$@"
      return $?
    elif (( $+functions[$candidate] )) || [[ -x "$dot_dir/bin/$candidate" ]]; then
      shift
      "$candidate" "$@"
      return $?
    fi
  fi

  local query="$*"
  local rows
  rows="$(_comma_gen_list "$dot_dir")"

  if [[ "$list_only" == true || ! -t 1 ]] || ! command -v fzf &>/dev/null; then
    if [[ -n "$query" ]]; then
      printf "%s\n" "$rows" | grep -i "$query"
    else
      printf "%s\n" "$rows"
    fi
    return 0
  fi

  local formatted
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' '{
    c_name = $1; orig = $2; desc = $3;
    printf "\033[1;38;2;203;166;247m%-14s\033[0m\t\033[38;2;137;180;250m%-18s\033[0m\t%s\t%s\t%s\n", c_name, orig, desc, c_name, orig
  }')

  local hdr="  j/k: move │ /: search │ enter: run │ e: insert on prompt │ h: help │ y: copy │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "⚡ Dotfiles Commands (,) > " "$hdr" "run" "e,h,y" "$query"

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --height=~55% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:green" \
    --preview='printf "\033[1;38;2;203;166;247m%s\033[0m (\033[1;38;2;137;180;250m%s\033[0m) — %s\n\n" {4} {5} {3}; which {5} 2>/dev/null | if command -v bat &>/dev/null; then bat -l zsh --color=always --style=plain; else cat; fi' \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selection" || return 0

  local first_line="${selected_lines%%$'\n'*}"
  local c1 c2 c3 comma_cmd orig_cmd
  IFS=$'\t' read -r c1 c2 c3 comma_cmd orig_cmd <<< "$first_line"
  [[ -z "$orig_cmd" ]] && return 0

  case "$key" in
    e)
      print -z "$orig_cmd "
      ;;
    h)
      "$orig_cmd" --help
      ;;
    y)
      _copy_or_print "$comma_cmd" "command: $comma_cmd"
      ;;
    *)
      # Commands that require a positional file/dir/url argument are placed on the prompt
      case "$orig_cmd" in
        take|extract|pack|clone|checksum|wpath|wcd)
          print -z "$orig_cmd "
          ;;
        *)
          "$orig_cmd"
          ;;
      esac
      ;;
  esac
}

# Tab completion for `,`: complete all custom dotfiles commands with descriptions
_comma() {
  local -a cmds
  local c_name orig desc
  while IFS=$'\t' read -r c_name orig desc; do
    [[ -n "$orig" ]] && cmds+=("${orig}:${desc}")
  done < <(_comma_gen_list 2>/dev/null)
  _describe 'dotfiles command' cmds
}
(( $+functions[compdef] )) && compdef _comma , || true
