# ==============================================================================
# Desktop Notifications & Long-Command Auto-Notify (`zsh/functions/notify.zsh`)
# ==============================================================================
# Cross-platform desktop and terminal notifications (`notify`) and automatic
# completion alerts for foreground commands exceeding 15s (`toggle-autonotify`).

# Cross-Platform Persistent Desktop & Terminal Notification
# Usage:
#   notify "Build finished!"
#   notify "Tests failed!" "Test Suite"
#   notify -b "Quick banner only"
#   npm run build && notify "Build succeeded!" || notify "Build failed!" "Error"
notify() {
  local banner_only=false
  if [ "$1" = "-b" ] || [ "$1" = "--banner" ]; then
    banner_only=true
    shift
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mnotify\033[0m (alias: \033[1malert\033[0m) — Persistent desktop & terminal notification (macOS, Linux, WSL)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  notify <message> [title]      Persistent alert that stays on screen until dismissed\n"
    printf "  notify -b <message> [title]   Transient corner banner only\n"
    return 0
  fi

  local msg="${1:-Command finished}"
  local title="${2:-Terminal}"

  # Terminal emulator desktop notification (Ghostty, WezTerm, Kitty, iTerm2 via OSC 777 & OSC 9)
  if [ -t 1 ]; then
    printf '\e]777;notify;%s;%s\e\\' "$title" "$msg" 2>/dev/null
    printf '\e]9;%s\a' "$msg" 2>/dev/null
  fi

  # 1. macOS: Persistent non-blocking floating alert + Notification Center banner + chime.
  # Passes $title and $msg via `on run argv` so quotes/backslashes in command strings never break AppleScript.
  if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"' -e 'end run' -- "$title" "$msg" 2>/dev/null || \
      osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' -- "$title" "$msg" 2>/dev/null || true
    if [ "$banner_only" = false ] && [ -t 1 ] && [ -z "$CI" ] && [ "$title" != "dottest" ]; then
      osascript -e 'on run argv' -e 'display alert (item 1 of argv) message (item 2 of argv) as informational buttons {"Dismiss"} default button "Dismiss"' -e 'end run' -- "$title" "$msg" &>/dev/null &!
    fi
    if [ -t 1 ] && [ "$title" != "dottest" ] && [ -f "/System/Library/Sounds/Glass.aiff" ]; then
      afplay "/System/Library/Sounds/Glass.aiff" &>/dev/null &!
    fi

  # 2. Linux: Persistent desktop notification (-u critical stays pinned until clicked/dismissed)
  elif command -v notify-send &>/dev/null; then
    if [ "$banner_only" = true ]; then
      notify-send "$title" "$msg" 2>/dev/null || true
    else
      notify-send -u critical "$title" "$msg" 2>/dev/null || notify-send "$title" "$msg" 2>/dev/null || true
    fi

  # 3. WSL: Persistent Windows 10/11 Toast Notification (scenario="reminder" stays until dismissed)
  # Passes title/message via environment variables so quotes or `$` never cause PowerShell injection.
  elif command -v powershell.exe &>/dev/null; then
    NOTIFY_TITLE="$title" NOTIFY_MSG="$msg" WSLENV="${WSLENV:+$WSLENV:}NOTIFY_TITLE/u:NOTIFY_MSG/u" \
      powershell.exe -NoProfile -Command '
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $xml = [xml]$template.GetXml()
        $toastNode = $xml.SelectSingleNode("/toast")
        if ($toastNode -ne $null) { $toastNode.SetAttribute("scenario", "reminder") }
        $xml.GetElementsByTagName("text")[0].AppendChild($xml.CreateTextNode($env:NOTIFY_TITLE)) > $null
        $xml.GetElementsByTagName("text")[1].AppendChild($xml.CreateTextNode($env:NOTIFY_MSG)) > $null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Terminal").Show($toast)
      ' 2>/dev/null || true

  # 4. Universal Fallback: ASCII Terminal Bell
  else
    printf "\a"
  fi

  # Terminal status output
  if [ -t 1 ]; then
    printf "\033[1;38;2;203;166;247m󰂚 [%s]\033[0m %s\n" "$title" "$msg"
  fi
}

typeset -g AUTO_NOTIFY_ENABLED="${AUTO_NOTIFY_ENABLED:-true}"

# Automatic Desktop Notification for Long-Running Foreground Commands (>15s)
toggle-autonotify() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;137;180;250mtoggle-autonotify\033[0m (alias: \033[1mautonotify\033[0m) — Toggle desktop notifications for commands >%ss\n" "${AUTO_NOTIFY_THRESHOLD:-15}"
    return 0
  fi
  if [ "$AUTO_NOTIFY_ENABLED" = "true" ]; then
    AUTO_NOTIFY_ENABLED="false"
    printf "\033[33m󰂛 Auto-notify disabled\033[0m (long-running commands will not send desktop alerts)\n"
  else
    AUTO_NOTIFY_ENABLED="true"
    printf "\033[32m󰂚 Auto-notify enabled\033[0m (commands >%ss will send desktop alerts)\n" "${AUTO_NOTIFY_THRESHOLD:-15}"
  fi
}

if [[ -o interactive ]]; then
  zmodload zsh/datetime 2>/dev/null || true
  typeset -g _auto_notify_cmd=""
  typeset -g _auto_notify_start=0

  _auto_notify_preexec() {
    _auto_notify_cmd="$1"
    _auto_notify_start="${EPOCHSECONDS:-0}"
  }

  _auto_notify_precmd() {
    local exit_status=$?
    if [ "${AUTO_NOTIFY_ENABLED:-true}" = "true" ] && (( _auto_notify_start > 0 )) && [ -n "$_auto_notify_cmd" ] && [ -n "$EPOCHSECONDS" ]; then
      local elapsed=$(( EPOCHSECONDS - _auto_notify_start ))
      local threshold="${AUTO_NOTIFY_THRESHOLD:-15}"
      if (( elapsed >= threshold )); then
        # Extract first command token (stripping leading sudo/env/time)
        local -a words
        words=(${(z)_auto_notify_cmd})
        local first_word="${words[1]:t}"
        while [[ "$first_word" == (sudo|env|time|nohup|command|builtin) ]] && (( ${#words[@]} > 1 )); do
          shift words
          first_word="${words[1]:t}"
        done

        # Ignore interactive TUIs, editors, pagers, and FZF shell pickers
        case "$first_word" in
          nvim|vim|vi|nano|emacs|code|yazi|y|lazygit|lg|btop|htop|top|man|less|more|ssh|mosh|tmux|zellij|fzf|gl|gco|gstash|ga|gadd|gfile|gfh|gsearch|wt|gwtdel|gwtclean|gbclean|conf|dotbranch|.branch|.b|scratch|fa|aliases|fenv|cheath|cheat|fjq|port|fport|fkill|kp|fcon|dps|fssh|fpkg|fbrew|fsize|bigfiles|fknown|proj|fp|snip|npmr|bunr|pnpmr|sdiff|strdiff|lastout|watch|fg|bg)
            ;;
          *)
            local mins=$(( elapsed / 60 ))
            local secs=$(( elapsed % 60 ))
            local dur_str="${secs}s"
            (( mins > 0 )) && dur_str="${mins}m ${secs}s"
            local short_cmd="${_auto_notify_cmd[1,48]}"
            if (( exit_status == 0 )); then
              notify "✔ ${short_cmd} (${dur_str})" "Command Completed" >/dev/null
            else
              notify "✖ ${short_cmd} (exit ${exit_status} after ${dur_str})" "Command Failed" >/dev/null
            fi
            ;;
        esac
      fi
    fi
    _auto_notify_cmd=""
    _auto_notify_start=0
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _auto_notify_preexec
  add-zsh-hook precmd _auto_notify_precmd
fi
