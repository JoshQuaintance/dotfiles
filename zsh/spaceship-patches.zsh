# ==============================================================================
# Spaceship Prompt & zsh-async Compatibility Patches
#
# Upstream Attributions:
#   - zsh-async: https://github.com/mafredri/zsh-async
#     Author: Mathias Fredriksson <mafredri@gmail.com>
#     License: BSD-2-Clause / MIT (Copyright (c) 2015 Mathias Fredriksson)
#   - Spaceship Prompt: https://github.com/spaceship-prompt/spaceship-prompt
#     Author: Denys Dovhan <denysdovhan@gmail.com>
#     License: MIT (Copyright (c) Denys Dovhan)
#
# Purpose:
#   Sourced by zsh/prompt.zsh immediately after spaceship.zsh loads to apply
#   targeted runtime hotfixes for asynchronous worker drain, terminal stderr
#   restoration, subshell error immunity, and mobile low-overhead fallbacks.
#   Each patch is self-contained and should be retired once upstream releases fix
#   the respective underlying behavior.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. zsh-async: Worker Result Buffer Drain Fix (WSL2 / Linux Kernel pty stalls)
#
# Adapted from: mafredri/zsh-async (async_process_results)
# Upstream: https://github.com/mafredri/zsh-async
# Author: Mathias Fredriksson
# License: BSD-2-Clause / MIT
#
# Issue:
#   zsh-async reads worker results with `zpty -r -t`, which on recent WSL2 and Linux
#   kernels returns only the leading NUL byte of a queued batch and reports "no data"
#   prematurely. Finished background jobs are silently dropped and the prompt hangs
#   indefinitely on the async "…" indicator.
#
# Fix:
#   Drain the worker's pty file descriptor directly with sysread (zsh/system)
#   when available, ensuring complete buffer consumption without worker stalls.
# ------------------------------------------------------------------------------
if (( $+functions[async_process_results] )) && zmodload zsh/system 2>/dev/null; then
    async_process_results() {
        setopt localoptions unset noshwordsplit noksharrays noposixidentifiers noposixstrings
        local worker=$1 callback=$2 caller=$3 null=$'\0' data
        local fd=${(k)ASYNC_PTYS[(r)$worker]}
        local -a items
        integer -l len pos num_processed has_next
        typeset -gA ASYNC_PROCESS_BUFFER

        while if [[ -n $fd ]]; then sysread -t 0 -i $fd -s 65536 data; else zpty -r -t $worker data 2>/dev/null; fi; do
            ASYNC_PROCESS_BUFFER[$worker]+=$data
            len=${#ASYNC_PROCESS_BUFFER[$worker]}
            pos=${ASYNC_PROCESS_BUFFER[$worker][(i)$null]}
            while (( len && pos <= len )); do
                items=("${(@Q)${(z)ASYNC_PROCESS_BUFFER[$worker][1,$pos-1]}}")
                ASYNC_PROCESS_BUFFER[$worker]=${ASYNC_PROCESS_BUFFER[$worker][$pos+1,$len]}
                len=${#ASYNC_PROCESS_BUFFER[$worker]}
                pos=${ASYNC_PROCESS_BUFFER[$worker][(i)$null]}
                has_next=$(( len != 0 ))
                if (( $#items == 5 )); then
                    $callback "${(@)items}" $has_next
                    (( num_processed++ ))
                elif [[ -n $items ]]; then
                    $callback "[async]" 1 "" 0 "$0: error: bad format, got ${#items} items (${(q)items})" $has_next
                fi
            done
        done

        (( num_processed )) && return 0
        [[ $caller = trap || $caller = watcher ]] && return 0
        return 1
    }
fi

# ------------------------------------------------------------------------------
# 2. Spaceship Prompt: Subshell & Strict Mode Directory Change Hardening
#
# Adapted from: spaceship-prompt/spaceship-prompt (prompt_spaceship_chpwd)
# Upstream: https://github.com/spaceship-prompt/spaceship-prompt
# Author: Denys Dovhan
# License: MIT
#
# Purpose:
#   Harden prompt_spaceship_chpwd with 'setopt localoptions noerrexit' so 'cd'
#   invocations within subshells or under 'set -e' never trigger shell termination.
# ------------------------------------------------------------------------------
if (( $+functions[prompt_spaceship_chpwd] )); then
    prompt_spaceship_chpwd() {
        setopt localoptions noerrexit
        (( ZSH_SUBSHELL == 0 )) && [[ -o zle ]] || return 0
        spaceship::worker::init
        spaceship::worker::eval builtin cd -q "$PWD"
        spaceship_exec_time_start
    }
fi

# ------------------------------------------------------------------------------
# 3. zsh-async: File Descriptor 2 (stderr) Leak Prevention (Issue #35)
#
# Reference: https://github.com/mafredri/zsh-async/issues/35
#
# Issue:
#   If a zpty worker collides on a worker name whose child process already exited,
#   zsh executes _async_worker in the parent shell and redirects fd 2 (stderr)
#   to /dev/null, silently breaking CLI utilities, Git hooks, and Atuin history.
#
# Fix:
#   Hook into precmd to detect closed/redirected stderr while stdout is on a TTY,
#   reopening fd 2 back to fd 1 via 'exec 2>&1'.
# ------------------------------------------------------------------------------
[[ -t 1 && ! -t 2 ]] && exec 2>&1
_heal_stderr_precmd() {
    [[ -t 1 && ! -t 2 ]] && exec 2>&1 || true
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _heal_stderr_precmd

# ------------------------------------------------------------------------------
# 4. Mobile & Low-Spec Terminal Optimization: Enforce Synchronous Rendering
#
# Purpose:
#   Enforce synchronous prompt rendering (SPACESHIP_PROMPT_ASYNC=false) on
#   mobile SSH, Blink, Termius, Termux, and narrow terminals to eliminate zpty
#   fork latency and background CPU/battery drain.
# ------------------------------------------------------------------------------
if [[ "${_IS_MOBILE:-false}" == true || -n "${SSH_MOBILE:-}" || "${LC_TERMINAL:-}" == (Blink|Termius|blink|termius) || "${TERM_PROGRAM:-}" == (Blink|Termius|blink|termius) ]]; then
    export SPACESHIP_PROMPT_ASYNC=false
    if (( $+functions[async_stop_worker] )); then
        async_stop_worker "spaceship" "spaceship_1" "spaceship_2" "spaceship_3" 2>/dev/null || true
    fi
fi
