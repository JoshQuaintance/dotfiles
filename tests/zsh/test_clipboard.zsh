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

test_copy_osc52_over_ssh_when_no_local_clipboard() {
  # Isolate PATH to a minimal directory without pbcopy/wl-copy/xclip/clip.exe
  mkdir -p "$HOME/osc_bin"
  ln -sf "$(command -v cat)" "$HOME/osc_bin/cat"
  ln -sf "$(command -v base64)" "$HOME/osc_bin/base64"
  ln -sf "$(command -v tr)" "$HOME/osc_bin/tr"
  local out
  out="$(PATH="$HOME/osc_bin" DISPLAY="" WAYLAND_DISPLAY="" WSL_DISTRO_NAME="" TMUX="" SSH_CONNECTION="1" DOTFILES_OSC52_STDOUT="1" copy <<< "hello-osc52")"
  local expected_b64
  expected_b64="$(printf "hello-osc52\n" | base64 | tr -d '\r\n')"
  assert_eq $'\033]52;c;'"${expected_b64}"$'\a' "$out"
}

test_copy_osc52_tmux_passthrough_and_buffer() {
  mkdir -p "$HOME/tmux_bin"
  ln -sf "$(command -v cat)" "$HOME/tmux_bin/cat"
  ln -sf "$(command -v base64)" "$HOME/tmux_bin/base64"
  ln -sf "$(command -v tr)" "$HOME/tmux_bin/tr"
  print -r -- '#!/bin/sh
if [ "$1" = "load-buffer" ]; then
  cat > "$HOME/tmux_buf"
elif [ "$1" = "save-buffer" ]; then
  cat "$HOME/tmux_buf"
fi' > "$HOME/tmux_bin/tmux"
  chmod +x "$HOME/tmux_bin/tmux"

  local out
  out="$(PATH="$HOME/tmux_bin" DISPLAY="" WAYLAND_DISPLAY="" WSL_DISTRO_NAME="" TMUX="/tmp/tmux-1000/default,123,0" DOTFILES_OSC52_STDOUT="1" copy <<< "tmux-clip")"
  local expected_b64
  expected_b64="$(printf "tmux-clip\n" | base64 | tr -d '\r\n')"
  assert_eq $'\033Ptmux;\033\033]52;c;'"${expected_b64}"$'\a\033\\' "$out"
  assert_eq "tmux-clip" "$(PATH="$HOME/tmux_bin" DISPLAY="" WAYLAND_DISPLAY="" WSL_DISTRO_NAME="" TMUX="/tmp/tmux-1000/default,123,0" clippaste)"
}

test_clip_transform_pipeline() {
  _stub_clipboard
  print -rn -- '  {"b":1,"a":[2,3]}  ' | copy
  clip --trim
  assert_eq '{"b":1,"a":[2,3]}' "$(clippaste)"
  local pretty
  pretty="$(clip --json -p)"
  assert_contains "$pretty" '"b": 1'
  assert_eq '{"b":1,"a":[2,3]}' "$(printf "%s" "$pretty" | clip --min -p)"

  print -rn -- $'zeta\nalpha\nzeta\nbeta' | copy
  assert_eq $'alpha\nbeta\nzeta' "$(clip --sort -p)"
  assert_eq 'HELLO WORLD' "$(printf 'hello world' | clip --upper -p)"
  assert_eq 'hello%20world%21' "$(printf 'hello world!' | clip --urlencode -p)"
  assert_eq 'hello world!' "$(printf 'hello%%20world%%21' | clip --urldecode -p)"
  assert_eq 'dGVzdC1iNjQ=' "$(printf 'test-b64' | clip --b64e -p)"
  assert_eq 'test-b64' "$(printf 'dGVzdC1iNjQ=' | clip --b64d -p)"
}

test_vi_mode_expand_path_and_yank_buffer_widgets() {
  _stub_clipboard
  source <(sed -n '/^_vi_expand_path_under_cursor() {/,/^}/p' "$DOTFILES_DIR/zsh/vi-mode.zsh")
  source <(sed -n '/^_vi_yank_buffer_to_clipboard() {/,/^}/p' "$DOTFILES_DIR/zsh/vi-mode.zsh")

  mkdir -p "$HOME/sub/nested"
  local LBUFFER="nvim ~/sub/nested/../" RBUFFER=" --flag" BUFFER="" CURSOR=0
  _vi_expand_path_under_cursor
  assert_eq "nvim ${HOME:A}/sub --flag" "$BUFFER"

  BUFFER="git status -sb"
  _vi_yank_buffer_to_clipboard
  assert_eq "git status -sb" "$(clippaste)"
}

test_lastout_captures_to_stdout_and_scratchpad() {
  export SCRATCH_DIR="$HOME/.test_lastout_scratch"
  local out
  out="$(lastout printf "captured-value-123")"
  assert_eq "captured-value-123" "$out"

  lastout -s echo "scratch-line-456" >/dev/null
  local daily_file="$SCRATCH_DIR/$(date +%Y-%m-%d).md"
  assert_file "$daily_file"
  assert_contains "$(<"$daily_file")" "scratch-line-456"
}

test_checksum_verifies_digest_and_detects_clipboard_digest() {
  _stub_clipboard
  printf "dotfiles-integrity-check" > "$HOME/sample.bin"
  local expected_sha256
  expected_sha256="$(python3 -c 'import hashlib; print(hashlib.sha256(b"dotfiles-integrity-check").hexdigest())')"

  local out
  out="$(checksum "$HOME/sample.bin" "$expected_sha256" | strip_ansi)"
  assert_contains "$out" "MATCH"
  assert_contains "$out" "Checksum verified (SHA-256 matched argument)"

  # Auto-match against clipboard when no 2nd argument is passed (via ,hash shorthand)
  print -rn -- "$expected_sha256" | copy
  local clip_out
  clip_out="$(,hash "$HOME/sample.bin" | strip_ansi)"
  assert_contains "$clip_out" "Checksum verified (SHA-256 matched clipboard)"

  # Mismatch returns non-zero
  local rc=0
  checksum "$HOME/sample.bin" "00000000000000000000000000000000" >/dev/null 2>&1 || rc=$?
  assert_eq 1 $rc

  # Multi-file & directory hashing via checksum (,hash) simply prints digests without comparing
  cp "$HOME/sample.bin" "$HOME/sample_copy.bin"
  printf "different-content" > "$HOME/sample_diff.bin"
  mkdir -p "$HOME/hashdir_a" "$HOME/hashdir_b"
  cp "$HOME/sample.bin" "$HOME/hashdir_a/item.bin"
  cp "$HOME/sample.bin" "$HOME/hashdir_b/item.bin"

  local multi_hash
  multi_hash="$(,hash "$HOME/sample.bin" "$HOME/sample_diff.bin" "$HOME/hashdir_a" | strip_ansi)"
  assert_contains "$multi_hash" "sample.bin"
  assert_contains "$multi_hash" "sample_diff.bin"
  assert_contains "$multi_hash" "hashdir_a/ (1 files,"

  # Explicit comparison via hashc (,hashc / ,hashcompare)
  local cmp_same
  cmp_same="$(,hashc "$HOME/sample.bin" "$HOME/sample_copy.bin" | strip_ansi)"
  assert_contains "$cmp_same" "All 2 targets are byte-for-byte identical"

  local cmp_dirs
  cmp_dirs="$(,hashcompare "$HOME/hashdir_a" "$HOME/hashdir_b" | strip_ansi)"
  assert_contains "$cmp_dirs" "All 2 targets are byte-for-byte identical"

  local cmp_diff rc_diff=0
  cmp_diff="$(hashc "$HOME/sample.bin" "$HOME/sample_diff.bin")" || rc_diff=$?
  cmp_diff="$(print -r -- "$cmp_diff" | strip_ansi)"
  assert_eq 1 $rc_diff
  assert_contains "$cmp_diff" "2 distinct SHA-256 digests across 2 targets"
}

test_netinfo_and_comma_launcher() {
  local out
  out="$(,net --no-ping | strip_ansi)"
  assert_contains "$out" "Network & Connectivity Diagnostic (netinfo)"
  assert_contains "$out" "Local IPv4:"
  assert_contains "$out" "DNS Servers:"

  local list_out
  list_out="$(, -l)"
  assert_contains "$list_out" $',net\tnetinfo\t'
  assert_contains "$list_out" $',hash\tchecksum\t'
  assert_contains "$list_out" $',pkg\tfpkg\t'
  assert_contains "$list_out" $',port\tport\t'

  # Direct dispatch via `, <cmd>` (single token after space) and `, <cmd> <args...>`
  assert_eq "hello-decode" "$(, decode 'aGVsbG8tZGVjb2Rl')"
  assert_contains "$(print 'aGVsbG8tZGVjb2Rl' | , decode)" "hello-decode"

  # Fish-like autosuggestions for `, <cmd>` and `, <cmd> <arg2>`
  local suggestion=""
  _zsh_autosuggest_strategy_comma ", pk"
  assert_eq ", pkg" "$suggestion"

  suggestion=""
  _zsh_autosuggest_strategy_comma ", gwtc"
  assert_eq ", gwtclean" "$suggestion"

  suggestion=""
  _zsh_autosuggest_strategy_comma ", dot doc"
  assert_eq ", dot doctor" "$suggestion"

  # Syntax highlighting for `, <cmd>` and `, <cmd> <arg2>`
  local BUFFER=", dot doctor --fix"
  local -a region_highlight=()
  _zsh_highlight_highlighter_comma_paint
  assert_contains "${(j: :)region_highlight}" "0 1 fg=green,underline"
  assert_contains "${(j: :)region_highlight}" "2 5 fg=green"
  assert_contains "${(j: :)region_highlight}" "6 12 fg=green"
  assert_contains "${(j: :)region_highlight}" "13 18 fg=cyan"

  BUFFER=", notacommand"
  region_highlight=()
  _zsh_highlight_highlighter_comma_paint
  assert_contains "${(j: :)region_highlight}" "2 13 fg=red,bold"
}
