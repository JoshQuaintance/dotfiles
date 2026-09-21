# Automatic Directory Listing on cd (_auto_ls)

_auto_ls() {
  # 1. Interactive & TTY guard: only run in interactive terminals with attached stdout
  [[ -o interactive ]] || return 0
  [[ -t 1 ]] || return 0

  # 2. Quick toggle guard (1 = enabled, 0 = disabled)
  [[ "${AUTO_LS:-1}" == "1" ]] || return 0

  # 3. File count threshold guard (default 35 items)
  local max="${AUTO_LS_MAX:-35}"
  local -a items=(*(N))
  local count="${#items}"

  if (( count == 0 )); then
    return 0
  elif (( count > max )); then
    print "\033[38;2;147;153;178m󰉋 $count items (threshold $max) — run \033[1;38;2;203;166;247m'l'\033[0;38;2;147;153;178m or \033[1;38;2;203;166;247m'll'\033[0;38;2;147;153;178m to view\033[0m"
  else
    if command -v eza &>/dev/null; then
      eza --icons --group-directories-first
    else
      ls -C
    fi
  fi
}

# Register the chpwd hook safely via add-zsh-hook
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _auto_ls

# Toggle function with support for on/off/status/custom threshold
toggle-autols() {
  case "$1" in
    on|enable|1)
      export AUTO_LS=1
      print "\033[38;2;166;227;161m✔ Auto-ls enabled\033[0m (threshold: ${AUTO_LS_MAX:-35} items)"
      _auto_ls
      ;;
    off|disable|0)
      export AUTO_LS=0
      print "\033[38;2;243;139;168m󰅙 Auto-ls disabled\033[0m"
      ;;
    status)
      if [[ "${AUTO_LS:-1}" == "1" ]]; then
        print "\033[38;2;166;227;161m✔ Auto-ls is enabled\033[0m (threshold: ${AUTO_LS_MAX:-35} items)"
      else
        print "\033[38;2;243;139;168m󰅙 Auto-ls is disabled\033[0m"
      fi
      ;;
    <->)
      export AUTO_LS_MAX="$1"
      export AUTO_LS=1
      print "\033[38;2;166;227;161m✔ Auto-ls threshold set to $1 items\033[0m"
      _auto_ls
      ;;
    *)
      if [[ "${AUTO_LS:-1}" == "1" ]]; then
        export AUTO_LS=0
        print "\033[38;2;243;139;168m󰅙 Auto-ls disabled\033[0m (toggle back with 'als')"
      else
        export AUTO_LS=1
        print "\033[38;2;166;227;161m✔ Auto-ls enabled\033[0m (threshold: ${AUTO_LS_MAX:-35} items)"
        _auto_ls
      fi
      ;;
  esac
}
