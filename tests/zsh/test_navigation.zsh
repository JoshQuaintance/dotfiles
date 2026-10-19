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
