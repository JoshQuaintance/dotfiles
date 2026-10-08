# Shared setup & assertions for tests/zsh/test_*.zsh (sourced by run.zsh in a fresh `zsh -f`).
# Assertions print what went wrong and exit the test's process with status 1.

source "$DOTFILES_DIR/zsh/functions.zsh"

fail() {
  print -r -- "$*"
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected: ${(q+)1}"$'\n'"actual:   ${(q+)2}${3:+$'\n'($3)}"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain ${(q+)2}"$'\n'"got: ${(q+)1}"
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_no_file() {
  [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

# Commit-ready throwaway repo: HOME is a temp dir, so pass identity & disable signing explicitly
git_test() {
  git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

strip_ansi() {
  sed $'s/\e\\[[0-9;]*m//g'
}
