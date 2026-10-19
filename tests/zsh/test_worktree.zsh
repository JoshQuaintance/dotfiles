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

test_gwts_parses_porcelain_and_marks_active_worktree() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch feature-1
  git_test worktree add -q ../feature-wt feature-1

  local out
  out="$(gwts | strip_ansi)"

  assert_contains "$out" "WORKTREE"
  assert_contains "$out" "BRANCH"
  assert_contains "$out" "➜ main_repo"
  assert_contains "$out" "feature-wt"
  assert_contains "$out" "feature-1"
  assert_contains "$out" "clean"
}

test_gwts_handles_detached_head_without_truncation() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test worktree add -q --detach ../detached-wt HEAD

  local out
  out="$(gwts | strip_ansi)"

  assert_contains "$out" "(detached HEAD)"
}

test_gwts_reports_untracked_and_staged_changes() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch feature-1
  git_test worktree add -q ../feature-wt feature-1

  touch ../feature-wt/new-untracked.txt
  touch staged.txt && git add staged.txt

  local out
  out="$(gwts | strip_ansi)"

  assert_contains "$out" "1 staged"
  assert_contains "$out" "1 untracked"
}

test_gwtdel_refuses_to_delete_active_worktree() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch other-feat
  git_test worktree add -q ../other-wt other-feat

  local out rc=0
  out="$(gwtdel main_repo 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "Cannot delete the active worktree"
}

test_gwtdel_refuses_to_delete_protected_branch() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch develop
  git_test worktree add -q ../develop-wt develop
  git_test branch feat-1
  git_test worktree add -q ../feat-1 feat-1

  local out rc=0
  out="$(gwtdel develop 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "No disposable worktree matching"
}

test_gwtdel_removes_worktree_and_local_branch_on_confirmation() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch feat-del
  git_test worktree add -q ../feat-del feat-del

  print "y\ny" | gwtdel feat-del >/dev/null || fail "gwtdel failed"

  assert_no_file "${HOME:A}/feat-del"
  local branches
  branches="$(git branch --list feat-del)"
  assert_eq "" "$branches"
}

test_gwtdel_removes_worktree_but_preserves_local_branch_when_declined() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch feat-keep
  git_test worktree add -q ../feat-keep feat-keep

  print "y\nn" | gwtdel feat-keep >/dev/null || fail "gwtdel failed"

  assert_no_file "${HOME:A}/feat-keep"
  local branches
  branches="$(git branch --list feat-keep)"
  assert_contains "$branches" "feat-keep"
}

test_gwtdel_aborts_when_deletion_declined() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "initial commit"
  git_test branch feat-abort
  git_test worktree add -q ../feat-abort feat-abort

  print "n" | gwtdel feat-abort >/dev/null

  assert_file "${HOME:A}/feat-abort/.git"
}
