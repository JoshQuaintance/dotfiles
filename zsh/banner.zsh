# Startup Summary Card (Catppuccin Mocha Left Accent Bar)

if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
    _t_total=$(( EPOCHREALTIME - _t_start ))
    _tot_str=$(printf "%.2fs" "$_t_total")
    _arch="${CPUTYPE:-$(uname -m)}"

    if [[ "$OSTYPE" == darwin* ]]; then
        _os_name="Darwin"
        _os_str="macOS (${_arch})"
    elif [[ "$OSTYPE" == linux* ]]; then
        _os_name="Linux"
        _os_str="Linux (${_arch})"
    else
        _os_name="$(uname -s)"
        _os_str="${_os_name} (${_arch})"
    fi

    # 1. Dotfiles info (fast shell reading without git subshell)
    _dot_branch=""
    _dot_hash=""
    if [ -f "$_dot_dir/.git/HEAD" ]; then
        read -r _head_line < "$_dot_dir/.git/HEAD"
        if [[ "$_head_line" == ref:\ * ]]; then
            _dot_branch="${_head_line#ref: refs/heads/}"
            _ref_file="$_dot_dir/.git/${_head_line#ref: }"
            if [ -f "$_ref_file" ]; then
                read -r _full_hash < "$_ref_file"
                _dot_hash="${_full_hash[1,7]}"
            fi
        else
            _dot_branch="detached"
            _dot_hash="${_head_line[1,7]}"
        fi
    fi
    [ -z "$_dot_branch" ] && _dot_branch="$(git -C "$_dot_dir" branch --show-current 2>/dev/null || echo "main")"
    [ -z "$_dot_hash" ] && _dot_hash="$(git -C "$_dot_dir" rev-parse --short HEAD 2>/dev/null || echo "")"
    _dot_info="${_dot_branch}${_dot_hash:+ (${_dot_hash})}"

    # 2. Battery status (macOS pmset pure Zsh matching + Linux sysfs /sys/class/power_supply)
    _batt_info=""
    _batt_label="Battery:"
    if command -v pmset &>/dev/null; then
        _batt_raw="$(pmset -g batt 2>/dev/null)"
        if [[ "$_batt_raw" =~ ([0-9]+%) ]]; then
            _batt_pct="${match[1]}"
            if [[ "${(L)_batt_raw}" == *"charging"* && "${(L)_batt_raw}" != *"not charging"* && "${(L)_batt_raw}" != *"discharging"* ]]; then
                _batt_info="${_batt_pct} ⚡"
            else
                _batt_info="${_batt_pct} 🔋"
            fi
        fi
    elif [ -d /sys/class/power_supply ]; then
        # Linux laptops (safely omit via (N) nullglob if in container or desktop)
        local -a _bats
        _bats=(/sys/class/power_supply/BAT*(N) /sys/class/power_supply/battery(N))
        for _bat in "${_bats[@]}"; do
            if [ -f "$_bat/capacity" ]; then
                read -r _pct_val < "$_bat/capacity" 2>/dev/null
                read -r _st < "$_bat/status" 2>/dev/null
                _pct="${_pct_val}%"
                if [ "$_st" = "Charging" ]; then
                    _batt_info="${_pct} ⚡"
                elif [ "$_st" = "Full" ]; then
                    _batt_info="${_pct} 🔌"
                else
                    _batt_info="${_pct} 🔋"
                fi
                break
            fi
        done
    fi

    if [ -z "$_batt_info" ]; then
        _batt_label="Network:"
        _batt_info="Online"
    fi

    # 3 & 4. System Uptime, CPU Load & Memory Stats (batched sysctl on macOS + Linux /proc)
    _uptime_str="N/A"
    _up_sec=0
    _cpu_load=""
    _mem_str="N/A"

    if [ "$_os_name" = "Darwin" ]; then
        _sysctl_out="$(sysctl -n kern.boottime vm.loadavg hw.memsize 2>/dev/null)"
        if [ -n "$_sysctl_out" ]; then
            local -a _sys_lines
            _sys_lines=("${(@f)_sysctl_out}")
            if [[ "${_sys_lines[1]}" =~ sec\ =\ ([0-9]+) ]]; then
                _up_sec=$(( EPOCHSECONDS - match[1] ))
            fi
            _tot_ram=$(( ${_sys_lines[3]:-0} / 1073741824 ))
        else
            _tot_ram=0
        fi
        if command -v vm_stat &>/dev/null; then
            _mem_str="$(vm_stat | awk -v tot="$_tot_ram" '
                /page size of/ { ps = substr($8, 1, length($8)) + 0 }
                /Pages active:/ { a = substr($3, 1, length($3)-1) + 0 }
                /Pages wired/ { w = substr($4, 1, length($4)-1) + 0 }
                /occupied by compressor:/ { c = substr($5, 1, length($5)-1) + 0 }
                END {
                    if (ps == 0) ps = 16384;
                    used = (a + w + c) * ps / (1024*1024*1024);
                    printf "%.0f/%.0fGB", used, tot;
                }
            ')"
        fi
    else
        [ -f /proc/uptime ] && _up_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
        [ -f /proc/loadavg ] && _cpu_load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
        if [ -f /proc/meminfo ]; then
            _mem_str="$(awk '/MemTotal:/ {tot=$2} /MemAvailable:/ {avail=$2} END { used=(tot-avail)/1048576; tot_gb=tot/1048576; printf "%.0f/%.0fGB", used, tot_gb }' /proc/meminfo 2>/dev/null)"
        fi
    fi

    if [ -n "$_up_sec" ] && [ "$_up_sec" -gt 0 ]; then
        _up_d=$(( _up_sec / 86400 ))
        _up_h=$(( (_up_sec % 86400) / 3600 ))
        _up_m=$(( (_up_sec % 3600) / 60 ))
        if [ "$_up_d" -gt 0 ]; then
            _uptime_str="${_up_d}d ${_up_h}h"
        elif [ "$_up_h" -gt 0 ]; then
            _uptime_str="${_up_h}h ${_up_m}m"
        else
            _uptime_str="${_up_m}m"
        fi
    fi

    # 5. Disk Space
    _disk_str="$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s (%s)", $4, $5}')"

    # 6. Rotating Shortcuts / Tips
    _tips=(
        "'dot' / '.status' → Quick workstation & dotfiles overview"
        "'npmr' / 'bunr'   → Interactive package.json script runner"
        "'.check' / '.update' → Check or update dotfiles & packages"
        "'.doctor' / '.test' → System health check & deep test suite"
        "'.bench' / '.clean' → Profile Zsh startup or prune stale caches"
        "'.branch'         → Switch active dotfiles branch & reload"
        "'groot' / 'gmain' → Jump to worktree or main repo root"
        "'scratch'         → Instant terminal notes & scratchpad manager"
        "'conf [target]'   → Browse or edit configs with auto-reload"
        "'wt' / 'gwts'     → Interactive worktree switcher & fleet dashboard"
        "'gwtn' / 'gwtenv' → Create worktree & sync untracked .env files"
        "'gwtdel' / 'gwtc' → Delete or prune merged git worktrees"
        "'x' / 'pack'      → Universal archive extractor & creator"
        "'up <N|dir>'      → Smart parent directory navigation"
        "'gbclean'         → Interactive merged git branch cleaner"
        "'gco' / 'gl'      → Modal Vim branch switcher & commit browser"
        "'ga' / 'gstash'   → Interactive git staging & stash manager"
        "'strdiff <a> <b>' → Colored character/word diff & scratch diff"
        "'take <dir>'      → mkdir -p and cd in one step"
        "'sz' / 'als'      → Reload ~/.zshrc or toggle auto-ls on cd"
        "'autonotify'      → Toggle desktop alerts for long commands (>15s)"
        "'fa' / 'aliases'  → Fuzzy search aliases, functions & comments"
        "'fenv' / 'cheath' → Inspect env vars or browse tldr cheat sheets"
        "'port' / 'fkill'  → Inspect or kill processes & ports"
    )
    _random_tip="${_tips[$(( (RANDOM % ${#_tips[@]}) + 1 ))]}"
    _tip_line="💡 ${_random_tip}"

    # Render Left Accent Bar
    printf "${_c_border}▌${_c_reset}\n"
    printf "${_c_border}▌${_c_reset} ${_c_title}%s${_c_reset} ${_c_dim}•${_c_reset} %s ${_c_dim}•${_c_reset} %s ${_c_dim}•${_c_reset} ${_c_check}Ready in %s${_c_reset}\n" \
        "$_title" "$_os_str" "zsh ${ZSH_VERSION:-5.9}" "$_tot_str"
    printf "${_c_border}▌${_c_reset} ${_c_key}Dotfiles:${_c_reset} %s\n" "$_dot_info"
    printf "${_c_border}▌${_c_reset} ${_c_key}System:${_c_reset}   %s up ${_c_dim}•${_c_reset} %s RAM ${_c_dim}•${_c_reset} %s Disk ${_c_dim}•${_c_reset} %s %s\n" \
        "$_uptime_str" "$_mem_str" "$_disk_str" "$_batt_label" "$_batt_info"
    printf "${_c_border}▌${_c_reset} ${_c_dim}%s${_c_reset}\n" "$_tip_line"
    echo ""
fi
