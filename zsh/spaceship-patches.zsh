# Spaceship / zsh-async workarounds, sourced by .zshrc right after spaceship.zsh loads.
# Each patch is self-contained: delete it once the upstream bug it describes is fixed.

# zsh-async reads worker results with `zpty -r -t`, which on recent WSL2 kernels returns only the
# leading NUL of a queued batch and then reports "no data" — finished jobs are silently dropped and
# the prompt sticks on the async "…" indicator. Drain the worker's pty fd with sysread instead.
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

# Harden prompt_spaceship_chpwd so 'cd' inside subshells or under 'set -e' never fails
if (( $+functions[prompt_spaceship_chpwd] )); then
    prompt_spaceship_chpwd() {
        setopt localoptions noerrexit
        (( ZSH_SUBSHELL == 0 )) && [[ -o zle ]] || return 0
        spaceship::worker::init
        spaceship::worker::eval builtin cd -q "$PWD"
        spaceship_exec_time_start
    }
fi

# Guard against zsh-async zpty bug (mafredri/zsh-async#35): if a zpty worker
# collides on a name whose child already exited, zsh runs _async_worker in the
# parent shell and redirects fd 2 (stderr) to /dev/null, breaking Atuin & git hooks.
[[ -t 1 && ! -t 2 ]] && exec 2>&1
_heal_stderr_precmd() {
    [[ -t 1 && ! -t 2 ]] && exec 2>&1 || true
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _heal_stderr_precmd
