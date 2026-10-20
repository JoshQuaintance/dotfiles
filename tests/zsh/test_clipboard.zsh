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
