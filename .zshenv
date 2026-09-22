# Ensure UTF-8 locale is always active and valid for Unicode & multibyte rendering
if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    _def_locale="en_US.UTF-8"
else
    _def_locale="C.UTF-8"
    if [ -d "/usr/lib/locale/en_US.utf8" ] || (command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qi "^en_US\.utf8$"); then
        _def_locale="en_US.UTF-8"
    fi
fi

# Override broken/unsupported locale if active on Linux
if [ "$_def_locale" = "C.UTF-8" ]; then
    if [ "$LANG" = "en_US.UTF-8" ] || [ "$LANG" = "en_US.utf8" ]; then
        export LANG="C.UTF-8"
    fi
    if [ "$LC_ALL" = "en_US.UTF-8" ] || [ "$LC_ALL" = "en_US.utf8" ]; then
        export LC_ALL="C.UTF-8"
    fi
fi

if [ -z "$LANG" ] || [ "$LANG" = "C" ] || [ "$LANG" = "POSIX" ]; then
    export LANG="$_def_locale"
fi
if [ -z "$LC_ALL" ] || [ "$LC_ALL" = "C" ] || [ "$LC_ALL" = "POSIX" ]; then
    export LC_ALL="$LANG"
fi
unset _def_locale

