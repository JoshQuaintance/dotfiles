# copy / clippaste. pbcopy & pbpaste are stubbed first on PATH, so this runs the same on every OS.

_stub_clipboard() {
  mkdir -p "$HOME/stubs"
  print -r -- '#!/bin/sh
cat > "$HOME/clipboard"' > "$HOME/stubs/pbcopy"
  print -r -- '#!/bin/sh
cat "$HOME/clipboard"' > "$HOME/stubs/pbpaste"
  chmod +x "$HOME/stubs/pbcopy" "$HOME/stubs/pbpaste"
  path=("$HOME/stubs" $path)
}

test_copy_then_clippaste_round_trips_unicode() {
  _stub_clipboard
  print -rn -- 'héllo → 🐧' | copy
  assert_eq 'héllo → 🐧' "$(clippaste)"
}

test_coreutils_paste_still_works() {
  assert_eq '1,2,3' "$(print -l 1 2 3 | paste -sd, -)"
}
