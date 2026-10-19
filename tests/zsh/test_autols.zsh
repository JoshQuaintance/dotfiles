# toggle-autols / _auto_ls

test_toggle_autols_explicit_on_and_off() {
  local out_on out_off
  out_on="$(toggle-autols on | strip_ansi)"
  assert_contains "$out_on" "Auto-ls enabled"

  toggle-autols on >/dev/null
  assert_eq "1" "$AUTO_LS"

  out_off="$(toggle-autols off | strip_ansi)"
  assert_contains "$out_off" "Auto-ls disabled"

  toggle-autols off >/dev/null
  assert_eq "0" "$AUTO_LS"
}

test_toggle_autols_threshold_setting() {
  local out
  out="$(toggle-autols 50 | strip_ansi)"
  assert_contains "$out" "Auto-ls threshold set to 50 items"

  toggle-autols 50 >/dev/null
  assert_eq "50" "$AUTO_LS_MAX"
  assert_eq "1" "$AUTO_LS"
}

test_toggle_autols_toggle_mode() {
  export AUTO_LS=1
  local out1
  out1="$(toggle-autols | strip_ansi)"
  assert_contains "$out1" "Auto-ls disabled"

  toggle-autols >/dev/null
  assert_eq "0" "$AUTO_LS"

  local out2
  out2="$(toggle-autols | strip_ansi)"
  assert_contains "$out2" "Auto-ls enabled"

  toggle-autols >/dev/null
  assert_eq "1" "$AUTO_LS"
}

test_toggle_autols_status() {
  export AUTO_LS=1
  local out_en
  out_en="$(toggle-autols status | strip_ansi)"
  assert_contains "$out_en" "Auto-ls is enabled"

  export AUTO_LS=0
  local out_dis
  out_dis="$(toggle-autols status | strip_ansi)"
  assert_contains "$out_dis" "Auto-ls is disabled"
}

test_auto_ls_respects_disabled_state() {
  export AUTO_LS=0
  local out
  out="$(_auto_ls)"
  assert_eq "" "$out"
}
