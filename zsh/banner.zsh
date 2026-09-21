# Startup Summary Card (Catppuccin Mocha Left Accent Bar)

if [ "$_ZSH_STARTUP_VERBOSE" = true ] && [ -n "$EPOCHREALTIME" ]; then
    _t_total=$(( EPOCHREALTIME - _t_start ))
    _tot_str=$(printf "%.2fs" "$_t_total")
    _arch="$(uname -m)"
    _os_name="$(uname -s)"

    if [ "$_os_name" = "Darwin" ]; then
        _os_str="macOS (${_arch})"
    else
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

    # 2. Battery status (macOS pmset + Linux sysfs /sys/class/power_supply)
    _batt_info=""
    _batt_label="Battery:"
    if command -v pmset &>/dev/null; then
        # macOS
        _batt_raw="$(pmset -g batt 2>/dev/null)"
        _batt_pct="$(echo "$_batt_raw" | grep -Eo '[0-9]+%' | head -n 1)"
        if [ -n "$_batt_pct" ]; then
            if echo "$_batt_raw" | grep -qi "charging" && ! echo "$_batt_raw" | grep -qi "not charging"; then
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
                _pct="$(cat "$_bat/capacity" 2>/dev/null)%"
                _st="$(cat "$_bat/status" 2>/dev/null)"
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

    # 3. System Uptime (macOS sysctl + Linux /proc/uptime)
    _uptime_str="N/A"
    _up_sec=0
    if [ "$_os_name" = "Darwin" ]; then
        _boot_sec="$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')"
        [ -n "$_boot_sec" ] && _up_sec=$(( EPOCHSECONDS - _boot_sec ))
    elif [ -f /proc/uptime ]; then
        _up_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
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

    # 4. CPU Load & Memory Stats (macOS vm_stat + Linux /proc)
    _cpu_load=""
    _mem_str="N/A"
    if [ "$_os_name" = "Darwin" ]; then
        _cpu_load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
        if command -v vm_stat &>/dev/null; then
            _tot_ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
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
        [ -f /proc/loadavg ] && _cpu_load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
        if [ -f /proc/meminfo ]; then
            _mem_str="$(awk '/MemTotal:/ {tot=$2} /MemAvailable:/ {avail=$2} END { used=(tot-avail)/1048576; tot_gb=tot/1048576; printf "%.0f/%.0fGB", used, tot_gb }' /proc/meminfo 2>/dev/null)"
        fi
    fi

    # 5. Disk Space
    _disk_str="$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s (%s)", $4, $5}')"

    # 6. Rotating Shortcuts / Tips
    _tips=(
        "'npmr' / 'bunr'   → Interactive script runner"
        "'.check' / '.update' → Check or update dotfiles"
        "'.doctor'         → System health & dotfiles diagnostics"
        "'groot'           → Jump to git project root"
        "'scratch'         → Instant terminal notes buffer"
        "'conf <target>'   → Edit config with fuzzy matcher & auto-reload"
        "'wt'              → Interactive git worktree switcher"
        "'x <archive>'     → Universal archive extractor"
        "'up <N|dir>'      → Smart parent directory navigation"
        "'gprune'          → Prune remote git branches"
        "'gbclean'         → Delete merged git branches"
        "'take <dir>'      → mkdir -p and cd in one step"
        "'sz'              → Reload ~/.zshrc and aliases"
        "'als'             → Toggle auto-ls after cd"
        "'fa' / 'aliases'  → Fuzzy search aliases & functions"
        "'port <port>'     → Show process on port"
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
