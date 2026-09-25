# System & Shell Productivity Helpers

port() {
  lsof -i :"$1"
}

# Yazi Shell Wrapper (changes directory on exit)
y() {
  local tmp
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  local cwd
  command yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp" 2>/dev/null)" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# Cross-Platform Clipboard Helpers (macOS, Linux Wayland, Linux X11, WSL)
copy() {
  if command -v pbcopy &>/dev/null; then
    pbcopy "$@"
  elif command -v wl-copy &>/dev/null; then
    wl-copy "$@"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard "$@"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --input "$@"
  elif command -v clip.exe &>/dev/null; then
    clip.exe "$@"
  elif [ -n "$TMUX" ]; then
    tmux load-buffer -
  else
    printf "\033[33mNo clipboard utility found (pbcopy, wl-copy, xclip, clip.exe)\033[0m\n" >&2
    return 1
  fi
}

paste() {
  if command -v pbpaste &>/dev/null; then
    pbpaste "$@"
  elif command -v wl-paste &>/dev/null; then
    wl-paste "$@"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard -o "$@"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --output "$@"
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command Get-Clipboard "$@"
  else
    printf "\033[33mNo clipboard utility found (pbpaste, wl-paste, xclip, powershell.exe)\033[0m\n" >&2
    return 1
  fi
}

# Universal Archive Extractor (extract / x)
extract() {
  if [ -z "$1" ]; then
    printf "\033[33mUsage: extract <archive_file>\033[0m\n" >&2
    printf "Supports: .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .zip, .rar, .7z, .tar.zst, .zst, .gz, .bz2\n" >&2
    return 1
  fi

  if [ ! -f "$1" ]; then
    printf "\033[31m✖ File not found: %s\033[0m\n" "$1" >&2
    return 1
  fi

  local file="$1"
  case "${file:l}" in
    *.tar.bz2|*.tbz2)   tar xvjf "$file" ;;
    *.tar.gz|*.tgz)     tar xvzf "$file" ;;
    *.tar.xz|*.txz)     tar xvJf "$file" ;;
    *.tar.zst)          tar --zstd -xvf "$file" 2>/dev/null || zstd -d -c "$file" | tar xvf - ;;
    *.tar)              tar xvf "$file" ;;
    *.bz2)              bunzip2 "$file" ;;
    *.rar)              unrar x "$file" ;;
    *.gz)               gunzip "$file" ;;
    *.zip)              unzip "$file" ;;
    *.z)                uncompress "$file" ;;
    *.7z)               7z x "$file" ;;
    *.zst)              zstd -d "$file" ;;
    *)
      printf "\033[31m✖ Cannot extract '%s' — unsupported extension.\033[0m\n" "$file" >&2
      return 1
      ;;
  esac
}

# Cross-Platform Desktop & Terminal Notification
# Usage:
#   notify "Build finished!"
#   notify "Tests failed!" "Test Suite"
#   npm run build && notify "Build succeeded!" || notify "Build failed!" "Error"
notify() {
  local msg="${1:-Command finished}"
  local title="${2:-Terminal}"

  # 1. macOS: Native Notification Center banner + subtle glass chime
  if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null
    if [ -f "/System/Library/Sounds/Glass.aiff" ]; then
      afplay "/System/Library/Sounds/Glass.aiff" &>/dev/null &!
    fi

  # 2. Linux: Desktop notification daemon (libnotify / notify-send)
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$msg" 2>/dev/null

  # 3. WSL: Native Windows 10/11 Toast Notification via PowerShell
  elif command -v powershell.exe &>/dev/null; then
    powershell.exe -NoProfile -Command "
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
      \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
      \$xml = [xml]\$template.GetXml()
      \$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('$title')) > \$null
      \$xml.GetElementsByTagName('text')[1].AppendChild(\$xml.CreateTextNode('$msg')) > \$null
      \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Terminal').Show(\$toast)
    " 2>/dev/null || true

  # 4. Universal Fallback: ASCII Terminal Bell
  else
    printf "\a"
  fi

  # Terminal status output
  if [ -t 1 ]; then
    printf "\033[1;38;2;203;166;247m󰂚 [%s]\033[0m %s\n" "$title" "$msg"
  fi
}
