# Interactive Package.json Script Selector (FZF)

_find_package_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/package.json" ]; then
      echo "$dir/package.json"
      return 0
    fi
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_extract_pkg_scripts() {
  local pkg_file="$1"
  if command -v jq &>/dev/null; then
    jq -r 'if .scripts then .scripts | to_entries[] | "\(.key)\t\(.value)" else empty end' "$pkg_file" 2>/dev/null
    return
  fi
  local js_rt=""
  command -v node &>/dev/null && js_rt="node" || { command -v bun &>/dev/null && js_rt="bun"; }
  [ -z "$js_rt" ] && return
  "$js_rt" -e '
    try {
      const pkg = JSON.parse(require("fs").readFileSync(process.argv.at(-1), "utf8"));
      for (const [k, v] of Object.entries(pkg.scripts || {})) console.log(k + "\t" + v);
    } catch {}
  ' -- "$pkg_file" 2>/dev/null
}

_pkg_script_select() {
  local runner="${1:-npm}"
  local pkg_file
  pkg_file=$(_find_package_json)

  if [ -z "$pkg_file" ] || [ ! -f "$pkg_file" ]; then
    printf "\033[31m✖ Cannot find a package.json file.\033[0m\n" >&2
    return 1
  fi

  local raw_scripts
  raw_scripts=$(_extract_pkg_scripts "$pkg_file")

  if [ -z "$raw_scripts" ]; then
    printf "\033[33mNo scripts found in %s\033[0m\n" "$pkg_file" >&2
    return 1
  fi

  if ! command -v fzf &>/dev/null; then
    printf "\033[33mfzf not found. Available scripts in %s:\033[0m\n" "$pkg_file" >&2
    printf "%s\n" "$raw_scripts"
    return 0
  fi

  local max_len
  max_len=$(echo "$raw_scripts" | awk -F'\t' 'BEGIN { max=0 } { if (length($1) > max) max=length($1) } END { if (max < 16) max=16; if (max > 32) max=32; print max }')

  local formatted
  formatted=$(echo "$raw_scripts" | awk -F'\t' -v len="$max_len" '{ printf "\033[1;36m%-" len "s\033[0m \033[90m│\033[0m %s\t%s\n", $1, $2, $1 }')

  local preview_cmd="
    s={2}
    ln=\$(grep -nF \"\\\"\$s\\\"\" '$pkg_file' 2>/dev/null | head -n1 | cut -d: -f1)
    if command -v bat &>/dev/null; then
      if [ -n \"\$ln\" ]; then
        start=\$(( ln > 10 ? ln - 10 : 1 ))
        end=\$(( ln + 25 ))
        bat --color=always --style=numbers --highlight-line \"\$ln\" --line-range \"\$start:\$end\" '$pkg_file' 2>/dev/null
      else
        bat --color=always --style=numbers '$pkg_file' 2>/dev/null
      fi
    else
      cat '$pkg_file' 2>/dev/null
    fi
  "

  local -a fzf_mode_flags
  _fzf_vim_mode "⚡ $runner run > " "  j/k: navigate │ /: search │ enter: run │ e: edit package.json │ y: copy cmd │ q: quit" "run" "e,y"

  local selection
  selection=$(echo "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1 \
    --height=~55% \
    --min-height=10 \
    --info=inline \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:cyan,pointer:bold:green" \
    --preview="$preview_cmd" \
    --preview-window="right:50%:wrap" \
    --expect="e,y")

  [ -z "$selection" ] && return 0

  local key
  key=$(echo "$selection" | head -n1)
  local selected_line
  selected_line=$(echo "$selection" | sed '1d')
  local selected
  selected=$(echo "$selected_line" | awk -F'\t' '{print $2}')

  [ -z "$selected" ] && return 0

  case "$key" in
    e)
      local ln
      ln=$(grep -nF "\"$selected\"" "$pkg_file" 2>/dev/null | head -n1 | cut -d: -f1)
      _edit_file "$pkg_file" "$ln"
      ;;
    y)
      local run_cmd="$runner run $selected"
      _copy_or_print "$run_cmd" "to clipboard: $run_cmd"
      ;;
    *)
      printf "\033[1;32m➜\033[0m \033[1;36m%s run %s\033[0m\n" "$runner" "$selected"
      command "$runner" run "$selected"
      ;;
  esac
}

# npm / bun / pnpm wrappers (intercept 'run' without arguments) & direct shortcuts (npmr, bunr, pnpmr)
for _pm in npm bun pnpm; do
  eval "
    ${_pm}() {
      if [ \"\$1\" = \"run\" ] && [ \"\$#\" -eq 1 ]; then
        _pkg_script_select ${_pm}
      else
        command ${_pm} \"\$@\"
      fi
    }
    ${_pm}r() {
      if ! _find_package_json >/dev/null; then
        printf \"\033[31m✖ Cannot find a package.json file.\033[0m\n\" >&2
        return 1
      fi
      if [ \"\$#\" -eq 0 ]; then
        _pkg_script_select ${_pm}
      else
        command ${_pm} run \"\$@\"
      fi
    }
  "
done
unset _pm
