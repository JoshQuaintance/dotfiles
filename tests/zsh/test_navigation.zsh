# take / up

test_take_creates_nested_dir_and_enters_it() {
  take a/b/c
  assert_eq "${HOME:A}/a/b/c" "${PWD:A}"
}

test_take_with_file_extension_creates_file_and_enters_dir() {
  take src/components/Button.tsx
  assert_eq "${HOME:A}/src/components" "${PWD:A}"
  assert_file "Button.tsx"
}

test_take_without_extension_creates_dir() {
  take my-folder
  assert_eq "${HOME:A}/my-folder" "${PWD:A}"
}

test_take_with_trailing_slash_creates_dir() {
  take site.com/
  assert_eq "${HOME:A}/site.com" "${PWD:A}"
}

test_groot_outside_git_repo_fails() {
  local out
  out="$(groot 2>&1)" || local rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "Not inside a git repository"
}

test_up_by_count() {
  mkdir -p x/y/z && cd x/y/z
  up 2 >/dev/null
  assert_eq "${HOME:A}/x" "${PWD:A}"
}

test_up_by_ancestor_name() {
  mkdir -p project/src/deep && cd project/src/deep
  up project >/dev/null
  assert_eq "${HOME:A}/project" "${PWD:A}"
}

test_up_defaults_to_one_level() {
  mkdir -p p/q/r && cd p/q/r
  up >/dev/null
  assert_eq "${HOME:A}/p/q" "${PWD:A}"
}

test_up_by_substring_ancestor() {
  mkdir -p project-analytics/src/utils && cd project-analytics/src/utils
  up analytics >/dev/null
  assert_eq "${HOME:A}/project-analytics" "${PWD:A}"
}

test_up_nonexistent_ancestor_fails_and_preserves_pwd() {
  mkdir -p p/q/r && cd p/q/r
  local out rc=0
  out="$(up nonexistent 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "No ancestor directory matching"
  assert_eq "${HOME:A}/p/q/r" "${PWD:A}"
}

test_up_help_flag_returns_zero() {
  local out rc=0
  out="$(up --help)" || rc=$?
  assert_eq 0 $rc
  assert_contains "$out" "Usage: up"
}

test_gmain_jumps_to_primary_repo_root_from_worktree() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "init"
  git_test worktree add -q ../wt-feature -b wt-feature
  cd ../wt-feature
  mkdir -p deep/nested/dir && cd deep/nested/dir

  gmain >/dev/null || fail "gmain failed"
  assert_eq "${HOME:A}/main_repo" "${PWD:A}"
}

test_d_index_out_of_range_fails() {
  local out rc=0
  out="$(d 99 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "out of range"
}

test_proj_discovers_repos_and_jumps_by_exact_name() {
  export DOTFILES_PROJECTS_DIR="$HOME/Codes"
  mkdir -p "$DOTFILES_PROJECTS_DIR"
  git_test init -q "$DOTFILES_PROJECTS_DIR/alpha-service"
  git_test -C "$DOTFILES_PROJECTS_DIR/alpha-service" checkout -q -b feat/login
  git_test init -q "$DOTFILES_PROJECTS_DIR/beta-web"

  local list_out
  list_out="$(proj -l)"
  assert_contains "$list_out" $'alpha-service\tfeat/login\t'
  assert_contains "$list_out" $'beta-web\t'

  proj alpha-service
  assert_eq "${DOTFILES_PROJECTS_DIR:A}/alpha-service" "${PWD:A}"
}

test_dotenv_loads_without_eval_and_unloads_cleanly() {
  cat > .env <<'EOF'
# Comment line
SIMPLE_KEY=hello_world # inline comment
export EXPORTED_KEY="quoted \"value\" with spaces" # trailing comment
SINGLE_QUOTED='$(echo should_not_execute)'
CRLF_KEY=win_value
EOF
  printf "CRLF_KEY=win_val\r\n" >> .env

  dotenv .env >/dev/null
  assert_eq "hello_world" "$SIMPLE_KEY"
  assert_eq 'quoted "value" with spaces' "$EXPORTED_KEY"
  assert_eq '$(echo should_not_execute)' "$SINGLE_QUOTED"
  assert_eq "win_val" "$CRLF_KEY"

  local list_out
  list_out="$(dotenv -l)"
  assert_contains "$list_out" "SIMPLE_KEY=hello_world"
  assert_contains "$list_out" "SINGLE_QUOTED=\$(echo should_not_execute)"

  dotenv -u >/dev/null
  assert_eq "" "${SIMPLE_KEY:-}"
  assert_eq "" "${EXPORTED_KEY:-}"
  assert_eq "" "${SINGLE_QUOTED:-}"
  assert_eq "" "${CRLF_KEY:-}"
}

test_fpkg_lists_brew_and_mise_packages() {
  mkdir -p "$HOME/pkg_stubs"
  print -r -- '#!/bin/sh
if [ "$2" = "--formula" ]; then
  printf "ripgrep 15.2.0\nfd 10.5.0\n"
elif [ "$2" = "--cask" ]; then
  printf "ghostty 1.2.0\n"
fi' > "$HOME/pkg_stubs/brew"
  print -r -- '#!/bin/sh
printf "node 24.21.0 ~/.config/mise/config.toml 24\n"' > "$HOME/pkg_stubs/mise"
  chmod +x "$HOME/pkg_stubs/brew" "$HOME/pkg_stubs/mise"

  local out
  out="$(PATH="$HOME/pkg_stubs:$PATH" fpkg -l)"
  assert_contains "$out" $'brew\tripgrep\t15.2.0'
  assert_contains "$out" $'cask\tghostty\t1.2.0'
  assert_contains "$out" $'mise\tnode\t24.21.0'
}
