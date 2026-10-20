# Internal helper: generate tab-delimited catalog of functions, bin tools, and aliases for `fa`
_fa_gen_list() {
  local dot_dir="${1:-${DOTFILES_DIR:-$HOME/.dotfiles}}"
  local -A alias_docs func_docs
  local k v

  # Extract inline '# comment' after alias definitions in .aliases / .aliases.local
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && alias_docs[$k]="$v"
  done < <(awk '
    /^[[:space:]]*alias[[:space:]]+[A-Za-z0-9_.-]+=/ && /#[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*alias[[:space:]]+/, "", line)
      name = line
      sub(/=.*/, "", name)
      comment = line
      sub(/^[^#]*#[[:space:]]*/, "", comment)
      if (name != "" && comment != "") print name "\t" comment
    }
  ' "$dot_dir/zsh/.aliases" "$HOME/.aliases.local" 2>/dev/null)

  # Extract header '# comment' above function definitions in zsh/functions/*.zsh
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && func_docs[$k]="$v"
  done < <(awk '
    /^#[[:space:]]+/ {
      line = $0
      sub(/^#[[:space:]]+/, "", line)
      if (line !~ /^(Usage:|===|---)/ && prev == "") prev = line
      next
    }
    /^[A-Za-z0-9_-]+\(\)[[:space:]]*\{/ {
      fn = $0
      sub(/\(\).*/, "", fn)
      if (prev != "") print fn "\t" prev
      prev = ""
      next
    }
    { prev = "" }
  ' "$dot_dir"/zsh/functions/*.zsh 2>/dev/null)

  # 1. Custom dotfiles functions (sourced from canonical DOTFILES_FUNCTIONS registry)
  local fn desc
  for fn in "${DOTFILES_FUNCTIONS[@]}"; do
    if (( $+functions[$fn] )); then
      desc="${func_docs[$fn]:-(shell function)}"
      printf "function\t%-18s\t%s\n" "$fn" "$desc"
    fi
  done

  # 2. Standalone dotfiles bin tools (parses '# Description: ...' header when present)
  if [ -d "$dot_dir/bin" ]; then
    local b bname bdesc
    for b in "$dot_dir/bin/"*; do
      if [ -x "$b" ]; then
        # :t = tail (basename) without forking a subshell
        bname="${b:t}"
        bdesc=$(awk '/^#[[:space:]]*Description:[[:space:]]*/ { sub(/^#[[:space:]]*Description:[[:space:]]*/, ""); print; exit } NR > 15 { exit }' "$b" 2>/dev/null)
        printf "tool\t%-18s\t%s\n" "$bname" "${bdesc:-(CLI utility in ~/.local/bin)}"
      fi
    done
  fi

  # 3. Active shell aliases (with inline comment from .aliases when present)
  local name val cmt
  alias | while IFS='=' read -r name val; do
    cmt="${alias_docs[$name]}"
    if [ -n "$cmt" ]; then
      printf "alias\t%-18s\t%s  # %s\n" "$name" "$val" "$cmt"
    else
      printf "alias\t%-18s\t%s\n" "$name" "$val"
    fi
  done
}

# Search Aliases & Functions (fa / aliases)
fa() {
  local dot_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local query=""
  local print_mode=false

  # Check flags: -p / --print or non-tty outputs raw text instead of interactive fzf
  if [ "$1" = "-p" ] || [ "$1" = "--print" ]; then
    print_mode=true
    shift
    query="$*"
  elif ! [ -t 1 ]; then
    print_mode=true
    query="$*"
  else
    query="$*"
  fi

  if [ "$print_mode" = true ]; then
    # Text-filtered output for pipes or when -p is specified
    if [ -n "$query" ]; then
      _fa_gen_list "$dot_dir" | awk -F'\t' -v q="$query" 'tolower($2) ~ tolower(q) || tolower($3) ~ tolower(q) {
        if ($1 == "alias")    printf "\033[38;2;137;180;250m[%s]\033[0m \033[1;38;2;203;166;247m%-18s\033[0m %s\n", $1, $2, $3
        if ($1 == "function") printf "\033[38;2;166;227;161m[%s]\033[0m \033[1;38;2;203;166;247m%-18s\033[0m %s\n", $1, $2, $3
        if ($1 == "tool")     printf "\033[38;2;249;226;175m[%s]\033[0m \033[1;38;2;203;166;247m%-18s\033[0m %s\n", $1, $2, $3
      }'
    else
      _fa_gen_list "$dot_dir"
    fi
  elif command -v fzf &>/dev/null; then
    local -a fzf_mode_flags
    _fzf_vim_mode "⚡ Aliases & Functions > " "  j/k: navigate │ /: search name or comment │ enter: paste │ q: quit" "paste" "" "$query"

    local selected
    selected=$(_fa_gen_list "$dot_dir" | fzf \
      --delimiter='\t' \
      --nth=2,3 \
      --with-nth=1,2,3 \
      --height=~45% \
      "${fzf_mode_flags[@]}" \
      --color="header:italic:dim,prompt:bold:magenta,pointer:bold:magenta" \
      --preview='printf "# %s\n" {3}; which {2} 2>/dev/null | if command -v bat &>/dev/null; then bat -l zsh --color=always --style=plain; else cat; fi' \
      --preview-window='right:55%:wrap')

    if [ -n "$selected" ]; then
      local cmd
      cmd=$(echo "$selected" | awk -F'\t' '{print $2}' | xargs)
      print -z "$cmd "
    fi
  else
    _fa_gen_list "$dot_dir" | awk -F'\t' -v q="$query" 'tolower($2) ~ tolower(q) || tolower($3) ~ tolower(q)'
  fi
}

# Internal helper: format sorted environment variables for `fenv`
_fenv_list_vars() {
  env | sort | awk -F'=' '
    /^[A-Za-z_][A-Za-z0-9_]*=/ {
      name = $1;
      val = substr($0, length(name) + 2);
      gsub(/\n/, " ", val);
      if (length(val) > 75) val = substr(val, 1, 72) "...";
      printf "\033[1;38;2;137;180;250m%-28s\033[0m\t%s\n", name, val
    }
  '
}

# Interactive Environment Variable Inspector (fenv)
# Usage:
#   fenv               -> Browse all environment variables in modal-Vim FZF with smart PATH breakdown
#   fenv <query>       -> Open filtered by <query> (e.g. fenv PATH, fenv FZF)
#   Keys: enter/y = copy value, n = copy NAME=VALUE, e = edit export on prompt
fenv() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mfenv\033[0m — Interactive modal-Vim environment variable inspector\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fenv               Browse all environment variables\n"
    printf "  fenv <query>       Open pre-filtered by <query> (e.g. fenv PATH)\n"
    printf "  Enter / y          Copy variable value to clipboard\n"
    printf "  n                  Copy NAME=VALUE to clipboard\n"
    printf "  e                  Insert 'export NAME=...' onto command line\n"
    return 0
  fi

  local query="$*"

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    if [ -n "$query" ]; then
      _fenv_list_vars | grep -i "$query"
    else
      _fenv_list_vars
    fi
    return 0
  fi

  local hdr="  j/k: navigate │ /: search │ enter/y: copy value │ n: copy KEY=VAL │ e: edit export │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "🌎 Environment > " "$hdr" "copy value" "y,n,e" "$query"

  local preview_cmd='
    k=$(printf "%s" {1} | sed "s/\x1b\[[0-9;]*[a-zA-Z]//g; s/ //g")
    v=$(printenv "$k" 2>/dev/null)
    printf "\033[1;38;2;203;166;247m%s\033[0m \033[2m(%d chars)\033[0m\n" "$k" "${#v}"
    printf "\033[38;2;108;112;134m────────────────────────────────────────────────────────\033[0m\n"
    if [[ "$k" == *PATH* ]] || [[ "$v" == /*:* ]]; then
      i=1
      IFS=":"
      for entry in $v; do
        [ -z "$entry" ] && continue
        if [ -e "$entry" ]; then
          printf "%2d. \033[32m✔\033[0m %s\n" "$i" "$entry"
        else
          printf "%2d. \033[31m✖\033[0m \033[2m%s (missing)\033[0m\n" "$i" "$entry"
        fi
        i=$((i + 1))
      done
    else
      printf "%s\n" "$v"
    fi
  '

  local selection
  selection=$(_fenv_list_vars | fzf \
    --ansi \
    --delimiter='\t' \
    --height=~55% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:blue,pointer:bold:magenta" \
    --preview="$preview_cmd" \
    --preview-window='right:55%:wrap')

  local key selected_lines selected_line
  _fzf_split_expect "$selection" || return 0
  selected_line="${selected_lines%%$'\n'*}"

  local var_name
  var_name=$(printf "%s" "$selected_line" | awk -F'\t' '{print $1}' | sed $'s/\x1b\\[[0-9;]*m//g' | tr -d ' ')
  [ -z "$var_name" ] && return 0
  local var_val="${(P)var_name}"

  case "$key" in
    e)
      print -z "export ${var_name}=${(qq)var_val}"
      ;;
    n)
      _copy_or_print "${var_name}=${var_val}" "${var_name}=<value> to clipboard"
      ;;
    *)
      _copy_or_print "$var_val" "value of ${var_name} to clipboard"
      ;;
  esac
}

# Interactive Cheat-Sheet Browser (cheath)
# Powered by tlrc (tldr) + modal-Vim FZF with live example previews
cheath() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mcheath\033[0m — Interactive modal-Vim CLI cheat-sheet browser (tldr)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  cheath             Browse all command cheat sheets in FZF\n"
    printf "  cheath <query>     Open pre-filtered by <query> (e.g. cheath tar)\n"
    printf "  Enter              Print full cheat sheet to terminal\n"
    printf "  e                  Insert command name onto Zsh prompt\n"
    return 0
  fi

  if ! command -v tldr &>/dev/null; then
    printf "\033[31m✖ 'tldr' (tlrc) is not installed.\033[0m\n" >&2
    return 1
  fi

  local pages
  pages="$(tldr --list 2>/dev/null)"
  if [ -z "$pages" ]; then
    tldr --update >/dev/null 2>&1 || true
    pages="$(tldr --list 2>/dev/null)"
  fi

  if [ -z "$pages" ]; then
    printf "\033[33mNo tldr pages available. Run 'tldr --update' to fetch pages.\033[0m\n" >&2
    return 1
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    if [ $# -gt 0 ]; then
      tldr "$@"
    else
      printf "%s\n" "$pages"
    fi
    return $?
  fi

  local query="$*"
  local hdr="  j/k: navigate │ /: search │ enter: print cheat sheet │ e: insert cmd │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "📚 Cheat Sheets > " "$hdr" "view" "e" "$query"

  local selection
  selection=$(printf "%s\n" "$pages" | fzf \
    --height=~60% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:cyan" \
    --preview='tldr --color always {} 2>/dev/null' \
    --preview-window='right:65%:wrap')

  local key selected_lines cmd_name
  _fzf_split_expect "$selection" || return 0
  cmd_name="${selected_lines%%$'\n'*}"
  [ -z "$cmd_name" ] && return 0

  if [ "$key" = "e" ]; then
    print -z "$cmd_name "
  else
    tldr --color always "$cmd_name"
  fi
}

# Interactive JSON / YAML / TOML Path Explorer (fjq)
# Powered by jq (+ yq for YAML/TOML) + modal-Vim FZF with live subtree preview
# Usage:
#   fjq <file.json|.yaml|.toml> -> Browse all paths & values interactively
#   cat data.json | fjq         -> Browse piped JSON/YAML payload interactively
#   Keys: enter = print value, y = copy value, p = copy jq path expression
fjq() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mfjq\033[0m — Interactive modal-Vim JSON/YAML/TOML path explorer (powered by jq & yq)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fjq <file>         Browse paths in .json, .yaml/.yml, or .toml file\n"
    printf "  cat a.json | fjq   Browse piped JSON/YAML from stdin\n"
    printf "  Enter              Output formatted value for selected path\n"
    printf "  y                  Copy extracted value to clipboard\n"
    printf "  p                  Copy jq path expression (e.g. .scripts.build) to clipboard\n"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    printf "\033[31m✖ 'jq' is not installed.\033[0m\n" >&2
    return 1
  fi

  local tmp_json=""
  local json_file=""
  setopt localoptions localtraps
  trap '[ -n "$tmp_json" ] && command rm -f -- "$tmp_json"' EXIT INT TERM
  if [ -n "$1" ]; then
    if [ ! -f "$1" ]; then
      printf "\033[31m✖ File not found: %s\033[0m\n" "$1" >&2
      return 1
    fi
    local input_file="$1"
    shift
    case "${input_file:l}" in
      *.yaml|*.yml)
        if ! command -v yq &>/dev/null; then
          printf "\033[31m✖ 'yq' is required to parse YAML files in fjq.\033[0m\n" >&2
          return 1
        fi
        tmp_json="$(mktemp -t "fjq-yaml.XXXXXX")"
        yq -o=json "$input_file" > "$tmp_json" 2>/dev/null
        json_file="$tmp_json"
        ;;
      *.toml)
        if ! command -v yq &>/dev/null; then
          printf "\033[31m✖ 'yq' is required to parse TOML files in fjq.\033[0m\n" >&2
          return 1
        fi
        tmp_json="$(mktemp -t "fjq-toml.XXXXXX")"
        yq -p=toml -o=json "$input_file" > "$tmp_json" 2>/dev/null
        json_file="$tmp_json"
        ;;
      *)
        json_file="$input_file"
        ;;
    esac
  elif [ ! -t 0 ]; then
    tmp_json="$(mktemp -t "fjq-stdin.XXXXXX")"
    cat > "$tmp_json"
    json_file="$tmp_json"
  else
    printf "\033[33mUsage: fjq <file.json|.yaml|.toml>  (or pipe JSON/YAML via stdin)\033[0m\n" >&2
    return 1
  fi

  # Enumerate all navigable jq paths with a compact value preview
  local jq_paths_filter='
    [
      paths | map(
        if type == "number" then "[\(.)]"
        elif test("^[A-Za-z_][A-Za-z0-9_]*$") then ".\(.)"
        else "[\(@json)]"
        end
      ) | join("") | if startswith("[") then "." + . else . end
    ] | unique | [".", .[]] | .[]
  '
  local paths
  paths=$(jq -r "$jq_paths_filter" "$json_file" 2>/dev/null)

  # Fallback: if stdin or extensionless file wasn't valid JSON, try converting via yq
  if [ -z "$paths" ] && command -v yq &>/dev/null; then
    local tmp_yq
    tmp_yq="$(mktemp -t "fjq-yq.XXXXXX")"
    if yq -o=json "$json_file" > "$tmp_yq" 2>/dev/null && [ -s "$tmp_yq" ]; then
      [ -n "$tmp_json" ] && rm -f -- "$tmp_json"
      tmp_json="$tmp_yq"
      json_file="$tmp_yq"
      paths=$(jq -r "$jq_paths_filter" "$json_file" 2>/dev/null)
    else
      rm -f -- "$tmp_yq"
    fi
  fi

  if [ -z "$paths" ]; then
    [ -n "$tmp_json" ] && rm -f -- "$tmp_json"
    printf "\033[31m✖ Invalid or empty JSON/YAML/TOML input.\033[0m\n" >&2
    return 1
  fi

  if [ ! -t 1 ] || ! command -v fzf &>/dev/null; then
    printf "%s\n" "$paths"
    [ -n "$tmp_json" ] && rm -f -- "$tmp_json"
    return 0
  fi

  local query="$*"
  local hdr="  j/k: navigate │ /: search path │ enter: print value │ y: copy value │ p: copy jq path │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "🧬 Data Explorer > " "$hdr" "print value" "y,p" "$query"

  local selection
  selection=$(printf "%s\n" "$paths" | fzf \
    --height=~60% \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:magenta,pointer:bold:cyan" \
    --preview="jq -C {} '$json_file' 2>/dev/null | head -n 120" \
    --preview-window='right:60%:wrap')

  local key selected_lines jq_path
  if ! _fzf_split_expect "$selection"; then
    [ -n "$tmp_json" ] && rm -f -- "$tmp_json"
    return 0
  fi
  jq_path="${selected_lines%%$'\n'*}"

  case "$key" in
    p)
      _copy_or_print "$jq_path" "jq path '$jq_path' to clipboard"
      ;;
    y)
      local extracted
      extracted=$(jq -r "$jq_path" "$json_file" 2>/dev/null)
      _copy_or_print "$extracted" "value of '$jq_path' to clipboard"
      ;;
    *)
      jq "$jq_path" "$json_file"
      ;;
  esac

  [ -n "$tmp_json" ] && rm -f -- "$tmp_json"
  return 0
}

# Tab completion for fjq: complete JSON, YAML, and TOML files
_fjq() {
  _files -g '*.(json|yaml|yml|toml)(-.)'
}
(( $+functions[compdef] )) && compdef _fjq fjq || true
