# ==============================================================================
# Installed Package Browser (`zsh/functions/packages.zsh`)
# ==============================================================================
# Interactive FZF inspector and manager (`fpkg` / `fbrew`) for Homebrew, Mise,
# and Linux system packages (apt, pacman, dnf).

# Internal helper: enumerate installed packages across Homebrew, Mise, and Linux package managers
# Output format: <manager>\t<package>\t<version>
_fpkg_list() {
  if command -v brew &>/dev/null; then
    brew list --formula --versions 2>/dev/null | awk 'NF>=2 {printf "brew\t%s\t%s\n", $1, $2}'
    brew list --cask --versions 2>/dev/null | awk 'NF>=2 {printf "cask\t%s\t%s\n", $1, $2}'
  fi
  if command -v mise &>/dev/null; then
    mise ls --current 2>/dev/null | awk 'NF>=2 {printf "mise\t%s\t%s\n", $1, $2}'
  fi
  if ! command -v brew &>/dev/null; then
    if command -v dpkg-query &>/dev/null; then
      dpkg-query -W -f='apt\t${Package}\t${Version}\n' 2>/dev/null
    elif command -v pacman &>/dev/null; then
      pacman -Q 2>/dev/null | awk 'NF>=2 {printf "pacman\t%s\t%s\n", $1, $2}'
    elif command -v rpm &>/dev/null; then
      rpm -qa --qf 'dnf\t%{NAME}\t%{VERSION}\n' 2>/dev/null | sort
    fi
  fi
}

# Interactive Package Inspector & Manager (fpkg / fbrew)
# Browse installed Homebrew, Mise, and Linux system packages in modal-Vim FZF
# Usage:
#   fpkg / fbrew       -> Browse all installed packages with info & dependency preview
#   fpkg <query>       -> Open filtered by <query> (e.g. fpkg ripgrep, fbrew node)
#   fpkg -l, --list    -> Print tab-separated table (<manager>\t<name>\t<version>)
#   Keys: enter = print info, u = upgrade, x = uninstall, o = open homepage, y = copy name
fpkg() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    printf "\033[1;38;2;249;226;175mfpkg\033[0m (alias: \033[1mfbrew\033[0m) — Interactive modal-Vim package inspector (Homebrew, Mise & Linux)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  fpkg / fbrew       Browse installed packages with live info & dependency preview\n"
    printf "  fpkg <query>       Open pre-filtered by <query>\n"
    printf "  fpkg -l, --list    Print tab-separated catalog of installed packages\n"
    printf "  Enter              Print full package metadata & dependency info\n"
    printf "  u                  Upgrade selected package(s)\n"
    printf "  x                  Uninstall selected package(s)\n"
    printf "  o                  Open package homepage in browser\n"
    printf "  y                  Copy package name(s) to clipboard\n"
    return 0
  fi

  local list_only=false
  if [[ "$1" == "-l" || "$1" == "--list" ]]; then
    list_only=true
    shift
  fi

  local query="$*"
  local rows
  rows="$(_fpkg_list)"
  if [[ -z "$rows" ]]; then
    printf "\033[33mNo installed packages found (brew, mise, apt, pacman, dnf).\033[0m\n" >&2
    return 1
  fi

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
    mgr = $1; pkg = $2; ver = $3;
    if (mgr == "brew")      m_col = sprintf("\033[38;2;249;226;175m%-8s\033[0m", mgr);
    else if (mgr == "cask") m_col = sprintf("\033[38;2;245;194;231m%-8s\033[0m", mgr);
    else if (mgr == "mise") m_col = sprintf("\033[38;2;203;166;247m%-8s\033[0m", mgr);
    else                    m_col = sprintf("\033[38;2;137;180;250m%-8s\033[0m", mgr);
    printf "%s\t\033[1m%-28s\033[0m\t\033[38;2;166;227;161m%s\033[0m\t%s\t%s\n", m_col, pkg, ver, mgr, pkg
  }')

  local hdr="  j/k: move │ space: select │ /: search │ enter: info │ u: upgrade │ x: uninstall │ o: home │ y: copy │ q: quit"
  local -a fzf_mode_flags
  _fzf_vim_mode "📦 Packages > " "$hdr" "info" "space,u,x,o,y" "$query" "space:toggle+down"

  local preview_cmd='
    mgr={4}; pkg={5}
    case "$mgr" in
      brew)
        brew info "$pkg" 2>/dev/null
        echo ""
        brew deps --tree --installed "$pkg" 2>/dev/null
        ;;
      cask)
        brew info --cask "$pkg" 2>/dev/null
        ;;
      mise)
        mise tool "$pkg" 2>/dev/null
        echo ""
        mise ls "$pkg" 2>/dev/null
        ;;
      apt)
        dpkg -s "$pkg" 2>/dev/null
        ;;
      pacman)
        pacman -Qi "$pkg" 2>/dev/null
        ;;
      dnf)
        rpm -qi "$pkg" 2>/dev/null
        ;;
    esac
  '

  local selection
  selection=$(printf "%s\n" "$formatted" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --multi \
    --height=~60% \
    --marker="✓ " \
    "${fzf_mode_flags[@]}" \
    --color="header:italic:dim,prompt:bold:yellow,pointer:bold:green,marker:bold:yellow" \
    --preview="$preview_cmd" \
    --preview-window='right:55%:wrap')

  local key="" selected_lines=""
  _fzf_split_expect "$selection" || return 0

  local -a pkgs=()
  local c1 c2 c3 mgr pkg
  while IFS=$'\t' read -r c1 c2 c3 mgr pkg; do
    [[ -n "$pkg" ]] && pkgs+=("$pkg")
    case "$key" in
      u)
        printf "\033[1;36m➜ Upgrading %s (%s)...\033[0m\n" "$pkg" "$mgr"
        case "$mgr" in
          brew)   brew upgrade "$pkg" ;;
          cask)   brew upgrade --cask "$pkg" ;;
          mise)   mise upgrade "$pkg" ;;
          apt)    sudo apt-get install --only-upgrade -y "$pkg" ;;
          pacman) sudo pacman -S "$pkg" ;;
          dnf)    sudo dnf upgrade -y "$pkg" ;;
        esac
        ;;
      x)
        printf "\033[1;31m➜ Uninstalling %s (%s)...\033[0m\n" "$pkg" "$mgr"
        case "$mgr" in
          brew)   brew uninstall "$pkg" ;;
          cask)   brew uninstall --cask "$pkg" ;;
          mise)   mise uninstall "$pkg" ;;
          apt)    sudo apt-get remove -y "$pkg" ;;
          pacman) sudo pacman -R "$pkg" ;;
          dnf)    sudo dnf remove -y "$pkg" ;;
        esac
        ;;
      o)
        case "$mgr" in
          brew) brew home "$pkg" ;;
          cask) brew home --cask "$pkg" ;;
          apt)
            local url
            url="$(dpkg -s "$pkg" 2>/dev/null | awk '/^Homepage:/ {print $2; exit}')"
            [[ -n "$url" ]] && open "$url"
            ;;
        esac
        ;;
      "")
        case "$mgr" in
          brew)   brew info "$pkg" ;;
          cask)   brew info --cask "$pkg" ;;
          mise)   mise tool "$pkg" ;;
          apt)    dpkg -s "$pkg" ;;
          pacman) pacman -Qi "$pkg" ;;
          dnf)    rpm -qi "$pkg" ;;
        esac
        ;;
    esac
  done <<< "$selected_lines"

  if [[ "$key" == "y" ]] && (( ${#pkgs[@]} > 0 )); then
    _copy_or_print "${(j: :)pkgs}" "package name(s): ${(j: :)pkgs}"
  fi
}
