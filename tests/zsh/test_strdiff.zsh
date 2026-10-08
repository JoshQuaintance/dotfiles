# strdiff (renamed from sdiff so diffutils' sdiff keeps working)

test_strdiff_reports_identical_strings() {
  assert_contains "$(strdiff same same | strip_ansi)" "identical"
}

test_strdiff_shows_both_versions() {
  local out
  out="$(strdiff 'feat/ABC-1' 'feat/ABD-1' | strip_ansi)"
  assert_contains "$out" "feat/ABC-1"
  assert_contains "$out" "feat/ABD-1"
}
