# scratch

test_scratch_help() {
  local out rc=0
  out="$(scratch -h | strip_ansi)" || rc=$?
  assert_eq 0 $rc
  assert_contains "$out" "scratch — Instant markdown scratchpad manager"
}

test_scratch_dir_jump() {
  export SCRATCH_DIR="$HOME/.test_scratch_dir"
  mkdir -p "$SCRATCH_DIR"
  scratch -d || fail "scratch -d failed"
  assert_eq "${SCRATCH_DIR:A}" "${PWD:A}"
}

test_scratch_piped_stdin_creates_named_pad() {
  export SCRATCH_DIR="$HOME/.test_scratch_pads"
  print "First note contents" | scratch test-pad >/dev/null || fail "piped scratch failed"
  assert_file "$SCRATCH_DIR/test-pad.md"
  assert_contains "$(<"$SCRATCH_DIR/test-pad.md")" "First note contents"
}

test_scratch_piped_stdin_appends_to_existing_pad() {
  export SCRATCH_DIR="$HOME/.test_scratch_pads"
  print "Line 1" | scratch multi-pad >/dev/null
  print "Line 2" | scratch multi-pad >/dev/null
  local content
  content="$(<"$SCRATCH_DIR/multi-pad.md")"
  assert_contains "$content" "Line 1"
  assert_contains "$content" "Line 2"
}

test_scratch_piped_stdin_creates_daily_scratchpad() {
  export SCRATCH_DIR="$HOME/.test_scratch_pads"
  print "Today entry" | scratch >/dev/null || fail "daily scratch failed"
  local daily_file="$SCRATCH_DIR/$(date +%Y-%m-%d).md"
  assert_file "$daily_file"
  assert_contains "$(<"$daily_file")" "Today entry"
}

test_scratch_grep_mode_finds_matching_pads() {
  export SCRATCH_DIR="$HOME/.test_scratch_pads"
  print "Alpha keyword search" | scratch pad-a >/dev/null
  print "Beta keyword search" | scratch pad-b >/dev/null

  local out
  out="$(scratch -g "Alpha" | strip_ansi)"
  assert_contains "$out" "pad-a.md"
  assert_contains "$out" "Alpha keyword search"
}

test_scratch_list_mode_without_tty() {
  export SCRATCH_DIR="$HOME/.test_scratch_pads"
  print "Sample entry" | scratch sample-pad >/dev/null

  local out
  out="$(scratch -l)"
  assert_contains "$out" "sample-pad.md"
}
