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
  ,hashcompare      hashc
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
#   , <cmd> [args...]  -> Execute custom command <cmd> directly (e.g. `, port`, `, pkg`, `, gwts`)
#   , <query>          -> Open palette pre-filtered by <query> when <query> is not an exact command
#   , -s <query>       -> Force-open palette pre-filtered by <query>
#   , -l, --list       -> Print tab-separated table of all `,` commands
,() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;203;166;247m,\033[0m (alias: \033[1mf\033[0m) — Interactive Dotfiles Command Palette & comma-prefix launcher\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  ,                    Browse & launch all custom dotfiles commands in FZF\n"
    printf "  ,<cmd> [args...]     Run any comma-prefixed command directly (e.g. ,port, ,pkg, ,net, ,hash)\n"
    printf "  , <cmd> [args...]    Dispatch to <cmd> even with a space after ',' (e.g. ', port', ', gwts')\n"
    printf "  , <query>            Open command palette filtered by <query> (if not an exact command)\n"
    printf "  , -s, --search <q>   Force-open command palette filtered by <q>\n"
    printf "  , -l, --list [query] List all comma-prefixed commands and descriptions\n"
    printf "  Enter                Execute selected command (or insert on prompt if it requires a path/arg)\n"
    printf "  e                    Insert command onto Zsh prompt to add flags/arguments\n"
    printf "  h                    Show --help for the selected command\n"
    printf "  y                    Copy command name to clipboard\n"
    return 0
  fi

  local list_only=false
  local search_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  elif [[ "$1" == "-s" || "$1" == "--search" ]]; then
    search_only=true
    shift
  fi

  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"

  # Direct dispatch when called as `, <cmd> [args...]` (with 1+ tokens and a known command)
  if [[ "$list_only" == false && "$search_only" == false ]] && (( $# >= 1 )); then
    local candidate="${1#,}"
    if (( $+functions[,$candidate] )); then
      shift
      ",$candidate" "$@"
      return $?
    elif (( ${DOTFILES_FUNCTIONS[(I)$candidate]} )) || [[ -x "$dot_dir/bin/$candidate" ]]; then
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
  formatted=$(printf "%s\n" "$rows" | awk -F'\t' '
    {
      c_name = $1; orig = $2; desc = $3;
      c_names[NR] = c_name; origs[NR] = orig; descs[NR] = desc;
      if (length(c_name) > w1) w1 = length(c_name);
      if (length(orig) > w2) w2 = length(orig);
    }
    END {
      if (w1 < 14) w1 = 14;
      if (w2 < 18) w2 = 18;
      for (i = 1; i <= NR; i++) {
        printf "\033[1;38;2;203;166;247m%-*s\033[0m\t\033[38;2;137;180;250m%-*s\033[0m\t%s\t%s\t%s\n", w1, c_names[i], w2, origs[i], descs[i], c_names[i], origs[i]
      }
    }
  ')

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
        take|extract|pack|clone|checksum|hashc|wpath|wcd)
          print -z "$orig_cmd "
          ;;
        *)
          "$orig_cmd"
          ;;
      esac
      ;;
  esac
}

# Resolve a comma command token (e.g. `pkg`, `,pkg`, `brew`, `gwts`) to its canonical command name.
_comma_resolve_target() {
  local token="${1#,}"
  local k v
  if [[ -n "${DOTFILES_COMMA_ALIASES[,$token]:-}" ]]; then
    printf "%s" "${DOTFILES_COMMA_ALIASES[,$token]}"
    return 0
  fi
  for k v in "${(@kv)DOTFILES_COMMA_SHORTHANDS}"; do
    if [[ "$v" == ",$token" ]]; then
      printf "%s" "$k"
      return 0
    fi
  done
  printf "%s" "$token"
}

# Tab completion for `,`: complete all custom dotfiles commands (both short comma names and canonical names)
# and delegate argument completion to the target command when completing positional arguments.
_comma() {
  if (( CURRENT > 2 )); then
    local subcmd
    subcmd="$(_comma_resolve_target "${words[2]}")"
    words=("$subcmd" "${words[@]:2}")
    (( CURRENT-- ))
    _normal
    return
  fi

  local -a cmds
  local -A seen
  local c_name orig desc short_name
  while IFS=$'\t' read -r c_name orig desc; do
    short_name="${c_name#,}"
    if [[ -n "$short_name" && -z "${seen[$short_name]:-}" ]]; then
      seen[$short_name]=1
      cmds+=("${short_name}:${desc}")
    fi
    if [[ -n "$orig" && -z "${seen[$orig]:-}" ]]; then
      seen[$orig]=1
      cmds+=("${orig}:${desc}")
    fi
  done < <(_comma_gen_list 2>/dev/null)
  _describe 'dotfiles command' cmds
}
(( $+functions[compdef] )) && compdef _comma , f || true

# Fish-like autosuggestion strategy for `, <cmd>` and `, <cmd> <args...>`.
# Registered in ZSH_AUTOSUGGEST_STRATEGY=(history comma completion).
_zsh_autosuggest_strategy_comma() {
  emulate -L zsh
  setopt EXTENDED_GLOB
  local prefix="$1"
  local -a match mbegin mend

  # 1. Completing the command name after `, ` or `f ` (e.g. `, pk` -> `, pkg`, `, gwtc` -> `, gwtclean`)
  if [[ "$prefix" =~ ^([[:space:]]*(,|f)[[:space:]]+)(,?)([A-Za-z0-9_-]+)$ ]]; then
    local lead="${match[1]}${match[3]}"
    local partial="${match[4]}"
    local fn short b bname
    for fn in "${(@koM)functions:#,*}"; do
      short="${fn#,}"
      if [[ "$short" == "${partial}"* && "$short" != "$partial" ]]; then
        typeset -g suggestion="${lead}${short}"
        return 0
      fi
    done
    for fn in "${(@o)DOTFILES_FUNCTIONS}"; do
      if [[ "$fn" == "${partial}"* && "$fn" != "$partial" ]]; then
        typeset -g suggestion="${lead}${fn}"
        return 0
      fi
    done
    for b in "${DOTFILES_DIR:-$HOME/.dotfiles}/bin/"*(N); do
      bname="${b:t}"
      if [[ "$bname" == "${partial}"* && "$bname" != "$partial" ]]; then
        typeset -g suggestion="${lead}${bname}"
        return 0
      fi
    done
    return 0
  fi

  # 2. Completing the 2nd+ argument after `, <cmd> <arg...>` (e.g. `, dot doc` -> `, dot doctor`)
  if [[ "$prefix" =~ ^([[:space:]]*(,|f)[[:space:]]+([^[:space:]]+)[[:space:]]+)(.*)$ ]]; then
    local cmd_lead="${match[1]}"
    local raw_cmd="${match[3]}"
    local rest="${match[4]}"
    local clean_cmd="${raw_cmd#,}"
    local canonical
    canonical="$(_comma_resolve_target "$clean_cmd")"

    if [[ "$canonical" == "dot" && "$rest" =~ ^[a-z]+$ ]]; then
      local sub
      for sub in status doctor test bench clean prune sync update backup env prompt help; do
        if [[ "$sub" == "${rest}"* && "$sub" != "$rest" ]]; then
          typeset -g suggestion="${cmd_lead}${sub}"
          return 0
        fi
      done
    fi

    # Search history for matching invocations of either `,<clean_cmd> <rest>*` or `<canonical> <rest>*`
    local pat1=",${clean_cmd} ${rest}*"
    local pat2="${canonical} ${rest}*"
    local hist_match="${history[(r)$pat1]:-}"
    if [[ -n "$hist_match" ]]; then
      typeset -g suggestion="${cmd_lead}${hist_match#*,${clean_cmd} }"
      return 0
    fi
    hist_match="${history[(r)$pat2]:-}"
    if [[ -n "$hist_match" ]]; then
      typeset -g suggestion="${cmd_lead}${hist_match#*${canonical} }"
      return 0
    fi
  fi
}

# Custom zsh-syntax-highlighting highlighter for `, <cmd> [args...]`.
# Registered in ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets comma).
_zsh_highlight_highlighter_comma_predicate() {
  _zsh_highlight_buffer_modified
}

_zsh_highlight_highlighter_comma_paint() {
  local buf="$BUFFER"
  local -a match mbegin mend
  [[ "$buf" =~ ^[[:space:]]*(,|f)[[:space:]]+([^[:space:]]+) ]] || return 0

  local c_start=$(( mbegin[1] - 1 )) c_end=$(( mend[1] ))
  local a_start=$(( mbegin[2] - 1 )) a_end=$(( mend[2] ))
  local raw_arg="${match[2]}"
  local candidate="${raw_arg#,}"
  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"

  local pre_style="${ZSH_HIGHLIGHT_STYLES[precommand]:-fg=green,underline}"
  local cmd_style="${ZSH_HIGHLIGHT_STYLES[function]:-fg=green}"
  local err_style="${ZSH_HIGHLIGHT_STYLES[unknown-token]:-fg=red,bold}"
  local sopt_style="${ZSH_HIGHLIGHT_STYLES[single-hyphen-option]:-fg=cyan}"
  local dopt_style="${ZSH_HIGHLIGHT_STYLES[double-hyphen-option]:-fg=cyan}"
  local path_style="${ZSH_HIGHLIGHT_STYLES[path]:-underline}"
  local memo=""
  (( ${zsh_highlight__memo_feature:-0} )) && memo=", memo=zsh-syntax-highlighting"

  region_highlight+=("$c_start $c_end ${pre_style}${memo}")

  if [[ "$raw_arg" == --* ]]; then
    region_highlight+=("$a_start $a_end ${dopt_style}${memo}")
    return 0
  elif [[ "$raw_arg" == -* ]]; then
    region_highlight+=("$a_start $a_end ${sopt_style}${memo}")
    return 0
  fi

  local is_valid=false
  if (( $+functions[,$candidate] || ${DOTFILES_FUNCTIONS[(I)$candidate]} )) || [[ -x "$dot_dir/bin/$candidate" ]]; then
    is_valid=true
  fi

  if [[ "$is_valid" == true ]]; then
    region_highlight+=("$a_start $a_end ${cmd_style}${memo}")
  else
    region_highlight+=("$a_start $a_end ${err_style}${memo}")
    return 0
  fi

  # Highlight subsequent arguments after `, <cmd> `
  local canonical
  canonical="$(_comma_resolve_target "$candidate")"
  local offset=$a_end
  local tail="${buf:$offset}"
  local arg_idx=0
  while [[ "$tail" =~ ^([[:space:]]+)([^[:space:]]+) ]]; do
    local ws_len=${#match[1]}
    local tok="${match[2]}"
    local tok_len=${#tok}
    local t_start=$(( offset + ws_len ))
    local t_end=$(( t_start + tok_len ))
    (( arg_idx++ ))

    if [[ "$tok" == --* ]]; then
      region_highlight+=("$t_start $t_end ${dopt_style}${memo}")
    elif [[ "$tok" == -* ]]; then
      region_highlight+=("$t_start $t_end ${sopt_style}${memo}")
    elif (( arg_idx == 1 )) && [[ "$canonical" == "dot" ]]; then
      case "$tok" in
        status|doctor|test|bench|clean|prune|sync|update|backup|env|prompt|help)
          region_highlight+=("$t_start $t_end ${cmd_style}${memo}")
          ;;
        *)
          region_highlight+=("$t_start $t_end ${err_style}${memo}")
          ;;
      esac
    elif [[ -e "${tok/#\~/$HOME}" ]]; then
      region_highlight+=("$t_start $t_end ${path_style}${memo}")
    fi

    offset=$t_end
    tail="${buf:$offset}"
  done
}
