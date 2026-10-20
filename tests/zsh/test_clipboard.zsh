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

test_fhash_verifies_checksum_and_detects_clipboard_digest() {
  _stub_clipboard
  printf "dotfiles-integrity-check" > "$HOME/sample.bin"
  local expected_sha256
  expected_sha256="$(python3 -c 'import hashlib; print(hashlib.sha256(b"dotfiles-integrity-check").hexdigest())')"

  local out
  out="$(fhash "$HOME/sample.bin" "$expected_sha256" | strip_ansi)"
  assert_contains "$out" "MATCH"
  assert_contains "$out" "Checksum verified (SHA-256 matched argument)"

  # Auto-match against clipboard when no 2nd argument is passed
  print -rn -- "$expected_sha256" | copy
  local clip_out
  clip_out="$(fhash "$HOME/sample.bin" | strip_ansi)"
  assert_contains "$clip_out" "Checksum verified (SHA-256 matched clipboard)"

  # Mismatch returns non-zero
  local rc=0
  fhash "$HOME/sample.bin" "00000000000000000000000000000000" >/dev/null 2>&1 || rc=$?
  assert_eq 1 $rc
}

test_fnet_renders_network_diagnostic_card() {
  local out
  out="$(fnet --no-ping | strip_ansi)"
  assert_contains "$out" "Network & Connectivity Diagnostic (fnet)"
  assert_contains "$out" "Local IPv4:"
  assert_contains "$out" "DNS Servers:"
}
