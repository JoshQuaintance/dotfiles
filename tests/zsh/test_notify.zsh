# notify / toggle-autonotify

test_notify_help_returns_zero() {
  local out rc=0
  out="$(notify -h | strip_ansi)" || rc=$?
  assert_eq 0 $rc
  assert_contains "$out" "notify (alias: alert) — Persistent desktop & terminal notification"
  assert_contains "$out" "Usage:"
}

test_toggle_autonotify_toggles_state() {
  export AUTO_NOTIFY_ENABLED=true

  local out1
  out1="$(toggle-autonotify | strip_ansi)"
  assert_contains "$out1" "Auto-notify disabled"

  toggle-autonotify >/dev/null
  assert_eq "false" "$AUTO_NOTIFY_ENABLED"

  local out2
  out2="$(toggle-autonotify | strip_ansi)"
  assert_contains "$out2" "Auto-notify enabled"

  toggle-autonotify >/dev/null
  assert_eq "true" "$AUTO_NOTIFY_ENABLED"
}

test_notify_banner_mode_executes_cleanly() {
  local rc=0
  CI=1 notify -b "Task completed" "Dotfiles Test" >/dev/null 2>&1 || rc=$?
  assert_eq 0 $rc
}
