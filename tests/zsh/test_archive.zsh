# pack / extract

test_pack_dir_then_extract_round_trips() {
  mkdir -p data/sub && print hello > data/sub/file.txt
  pack data >/dev/null || fail "pack failed"
  assert_file data.tar.gz
  mkdir out && mv data.tar.gz out/ && cd out
  extract data.tar.gz >/dev/null || fail "extract failed"
  assert_eq hello "$(<data/sub/file.txt)"
}

test_pack_zip_from_explicit_name() {
  (( $+commands[zip] && $+commands[unzip] )) || return 0
  print one > a.txt && print two > b.txt
  pack bundle.zip a.txt b.txt >/dev/null || fail "pack failed"
  mkdir out && cd out
  extract ../bundle.zip >/dev/null || fail "extract failed"
  assert_eq two "$(<b.txt)"
}
