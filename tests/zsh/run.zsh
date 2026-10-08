#!/usr/bin/env zsh
# Unit tests for the shell functions in zsh/functions/*.zsh (macOS, Linux & WSL).
#   zsh tests/zsh/run.zsh             -> run every tests/zsh/test_*.zsh
#   zsh tests/zsh/run.zsh worktree    -> only files whose name contains "worktree"
# Each test_* function runs in a fresh `zsh -f` inside its own temp dir, with HOME pointed there,
# so tests never touch the real home directory or depend on the user's ~/.zshrc.

emulate -R zsh
ROOT="${0:A:h:h:h}"
filter="${1:-}"
integer passed=0 failed=0
local -a failures=()

if [[ -t 1 ]]; then
  c_ok=$'\e[32m' c_fail=$'\e[31m' c_dim=$'\e[2m' c_reset=$'\e[0m'
else
  c_ok="" c_fail="" c_dim="" c_reset=""
fi

for file in "$ROOT"/tests/zsh/test_*.zsh(N); do
  [[ -n $filter && ${file:t} != *$filter* ]] && continue
  tests=(${(f)"$(DOTFILES_DIR="$ROOT" zsh -f -c "source ${(q)file}; print -l \${(ok)functions[(I)test_*]}")"})
  print "${c_dim}${file:t}${c_reset}"

  for t in $tests; do
    tmp="$(mktemp -d)" || exit 1
    output="$(cd "$tmp" && HOME="$tmp" DOTFILES_DIR="$ROOT" zsh -f -c \
      "source ${(q)ROOT}/tests/zsh/lib.zsh && source ${(q)file} && $t" 2>&1)"
    rc=$?
    [[ -n $tmp && -d $tmp ]] && command rm -rf -- "$tmp"

    if (( rc == 0 )); then
      (( passed++ ))
      print "  ${c_ok}✔${c_reset} $t"
    else
      (( failed++ ))
      failures+=("${file:t}::$t")
      print "  ${c_fail}✖ $t${c_reset}"
      [[ -n $output ]] && print -r -- "$output" | sed 's/^/    /'
    fi
  done
done

print "\n${passed} passed, ${failed} failed"
(( failed == 0 ))
