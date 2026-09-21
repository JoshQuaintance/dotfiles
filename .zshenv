# Ensure UTF-8 locale is always active for all Zsh invocations, subshells, and scripts
if [ -z "$LANG" ] || [ "$LANG" = "C" ] || [ "$LANG" = "POSIX" ]; then
    export LANG="en_US.UTF-8"
fi
if [ -z "$LC_ALL" ] || [ "$LC_ALL" = "C" ] || [ "$LC_ALL" = "POSIX" ]; then
    export LC_ALL="$LANG"
fi
