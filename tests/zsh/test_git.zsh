# clone -b / gco / _git_base_branch

test_clone_bare_hub_creates_worktree_and_switches() {
  git_test init -q upstream_repo
  cd upstream_repo
  git_test commit -q --allow-empty -m "initial commit"
  cd ..

  clone -b "file://$PWD/upstream_repo" hub >/dev/null || fail "clone -b returned non-zero"

  assert_eq "${HOME:A}/hub/main" "${PWD:A}"
  assert_file "${HOME:A}/hub/.bare/config"
  assert_eq "gitdir: ./.bare" "$(<"${HOME:A}/hub/.git")"
  assert_file "${HOME:A}/hub/main/.git"
  assert_no_file "${HOME:A}/hub/hub"
}

test_clone_bare_hub_respects_custom_default_branch() {
  git_test init -b develop -q dev_source
  cd dev_source
  git_test commit -q --allow-empty -m "dev init"
  cd ..

  clone -b "file://$PWD/dev_source" devhub >/dev/null || fail "clone -b with develop returned non-zero"

  assert_eq "${HOME:A}/devhub/develop" "${PWD:A}"
  assert_eq "develop" "$(git -C "${HOME:A}/devhub/develop" branch --show-current)"
}

test_clone_normal_repo() {
  git_test init -q normal_source
  cd normal_source
  git_test commit -q --allow-empty -m "normal init"
  cd ..

  clone "file://$PWD/normal_source" normal_clone >/dev/null || fail "clone returned non-zero"

  assert_eq "${HOME:A}/normal_clone" "${PWD:A}"
  assert_file "${HOME:A}/normal_clone/.git/config"
  assert_no_file "${HOME:A}/normal_clone/.bare"
}

test_git_base_branch_detection_hierarchy() {
  git_test init -q -b main test_repo
  cd test_repo
  git_test commit -q --allow-empty -m "init"
  assert_eq "main" "$(_git_base_branch)"

  git_test branch master
  assert_eq "master" "$(_git_base_branch)"

  git_test branch develop
  assert_eq "develop" "$(_git_base_branch)"
}

test_git_base_branch_detects_remote_develop() {
  git_test init -q origin_dev
  cd origin_dev
  git_test checkout -q -b develop
  git_test commit -q --allow-empty -m "origin dev"
  cd ..

  git_test clone -q "file://$PWD/origin_dev" local_clone
  cd local_clone
  git_test checkout -q -b feature-temp
  git_test branch -d develop >/dev/null
  assert_eq "develop" "$(_git_base_branch)"
}

test_gco_switches_to_slashed_local_branch() {
  git_test init -q slash_repo
  cd slash_repo
  git_test commit -q --allow-empty -m "init"
  git_test branch feat/sales-3709/dialog-flow

  gco feat/sales-3709/dialog-flow >/dev/null || fail "gco failed"
  assert_eq "feat/sales-3709/dialog-flow" "$(git branch --show-current)"
}

test_gco_outside_git_repo_fails() {
  local out rc=0
  out="$(gco 2>&1)" || rc=$?
  (( rc != 0 )) || fail "expected non-zero exit code outside git repo"
  assert_contains "$out" "not a git repository"
}
