#!/usr/bin/env zsh
# Unit tests for modal-Vim FZF state machine (_fzf_vim_mode).

test_fzf_vim_mode_expect_keys_unbound_in_search() {
  local -a fzf_mode_flags=()
  _fzf_vim_mode "⚡ npm run > " "header" "run" "e,y"

  local flags_str="${(F)fzf_mode_flags}"

  # Base binds must contain modal print actions
  assert_contains "$flags_str" "enter:print()+accept"
  assert_contains "$flags_str" "e:print(e)+accept"
  assert_contains "$flags_str" "y:print(y)+accept"

  # Search mode transition must unbind modal keys including e and y
  assert_contains "$flags_str" "unbind(j,k,q,g,G,e,y,i,/)"

  # Normal mode transition must rebind modal keys and unbind esc
  assert_contains "$flags_str" "rebind(j,k,q,g,G,e,y,i,/)"
}

test_fzf_vim_mode_no_expect_keys_uses_plain_accept() {
  local -a fzf_mode_flags=()
  _fzf_vim_mode "🌿 Worktree > " "header" "cd"

  local flags_str="${(F)fzf_mode_flags}"

  # When no expect keys are requested, Enter must be standard accept
  assert_contains "$flags_str" "enter:accept"
  # Should unbind navigation and search triggers
  assert_contains "$flags_str" "unbind(j,k,q,g,G,i,/)"
}

test_fzf_vim_mode_extra_binds_preserved() {
  local -a fzf_mode_flags=()
  _fzf_vim_mode "🗑 Prune > " "header" "confirm" "space,a" "" "space:toggle+down,a:toggle-all"

  local flags_str="${(F)fzf_mode_flags}"

  # Custom in-fzf actions should be kept and not converted to expect keys
  assert_contains "$flags_str" "space:toggle+down"
  assert_contains "$flags_str" "a:toggle-all"
  assert_contains "$flags_str" "enter:accept"
}

test_fzf_split_expect_parses_key_and_lines() {
  local key="" selected_lines=""
  _fzf_split_expect $'ctrl-v\nfirst-item\nsecond-item' || fail "expected split to succeed"
  assert_eq "ctrl-v" "$key"
  assert_eq $'first-item\nsecond-item' "$selected_lines"

  # Enter key produces an empty first line followed by the selected item
  _fzf_split_expect $'\nonly-item' || fail "expected empty-key split to succeed"
  assert_eq "" "$key"
  assert_eq "only-item" "$selected_lines"

  # Empty or single-line input (cancelled selection) must return non-zero
  if _fzf_split_expect ""; then
    fail "expected empty input to return non-zero"
  fi
}
