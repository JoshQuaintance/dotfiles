# _copy_worktree_env (used by gwtnew & gwtenv): untracked .env files follow you into new worktrees

_repo_with_feature_worktree() {
  git_test init -q main && cd main
  git_test commit -q --allow-empty -m init
  print 'SECRET=1' > .env
  mkdir -p api && print 'API=1' > api/.env.local
  git_test worktree add -q ../feature -b feature
}

test_env_files_are_copied() {
  _repo_with_feature_worktree
  _copy_worktree_env "$PWD" "${PWD:h}/feature" "" "" true >/dev/null || fail "returned non-zero"
  assert_eq 'SECRET=1' "$(<../feature/.env)"
  assert_eq 'API=1' "$(<../feature/api/.env.local)"
}

test_existing_env_is_kept_without_force() {
  _repo_with_feature_worktree
  print 'MINE=1' > ../feature/.env
  _copy_worktree_env "$PWD" "${PWD:h}/feature" "" "" true >/dev/null
  assert_eq 'MINE=1' "$(<../feature/.env)"
}

test_force_overwrites_untracked_env() {
  _repo_with_feature_worktree
  print 'MINE=1' > ../feature/.env
  _copy_worktree_env "$PWD" "${PWD:h}/feature" "" "" true true >/dev/null
  assert_eq 'SECRET=1' "$(<../feature/.env)"
}

test_answering_no_skips_copy() {
  _repo_with_feature_worktree
  print n | _copy_worktree_env "$PWD" "${PWD:h}/feature" "" "" false >/dev/null
  assert_no_file ../feature/.env
}

test_bare_clone_heals_fetch_and_lists_unattached_branches() {
  git_test init -q origin_repo
  git_test -C origin_repo checkout -q -b develop
  git_test -C origin_repo commit -q --allow-empty -m "initial"
  git_test -C origin_repo branch feat/SALES-3709/rule-crud
  git_test -C origin_repo branch feat/SALES-3706/relay-inbox

  # Simulate manual `git clone --bare` which omits remote.origin.fetch and puts branches in refs/heads/*
  git_test clone -q --bare "$PWD/origin_repo" hub/.bare
  echo "gitdir: ./.bare" > hub/.git
  git_test -C hub worktree add -q "$PWD/hub/develop" develop
  cd hub/develop

  _gwt_ensure_origin_fetch
  assert_eq '+refs/heads/*:refs/remotes/origin/*' "$(git config --get remote.origin.fetch)"

  local avail
  avail="$(_gwtnew_available_branches)"
  assert_contains "$avail" "feat/SALES-3709/rule-crud"
  assert_contains "$avail" "feat/SALES-3706/relay-inbox"
}
