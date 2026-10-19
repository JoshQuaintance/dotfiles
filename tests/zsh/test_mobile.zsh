source "$DOTFILES_DIR/zsh/prompt.zsh"

test_dotfiles_detect_prompt_env_override() {
  local res1 res2
  res1="$(DOTFILES_PROMPT=native _dotfiles_detect_prompt)"
  assert_eq "native" "$res1"

  res2="$(DOTFILES_PROMPT=spaceship _dotfiles_detect_prompt)"
  assert_eq "spaceship" "$res2"
}

test_mobile_ssh_environment_forces_native_prompt() {
  local res
  res="$(unset DOTFILES_PROMPT; SSH_MOBILE=1 _dotfiles_detect_prompt)"
  assert_eq "native" "$res"
}

test_mobile_lc_terminal_blink_forces_native_prompt() {
  local res_blink res_termius
  res_blink="$(unset DOTFILES_PROMPT; LC_TERMINAL=Blink _dotfiles_detect_prompt)"
  assert_eq "native" "$res_blink"

  res_termius="$(unset DOTFILES_PROMPT; LC_TERMINAL=Termius _dotfiles_detect_prompt)"
  assert_eq "native" "$res_termius"
}

test_mobile_term_program_blink_forces_native_prompt() {
  local res_blink res_termius
  res_blink="$(unset DOTFILES_PROMPT; TERM_PROGRAM=Blink _dotfiles_detect_prompt)"
  assert_eq "native" "$res_blink"

  res_termius="$(unset DOTFILES_PROMPT; TERM_PROGRAM=Termius _dotfiles_detect_prompt)"
  assert_eq "native" "$res_termius"
}

test_mobile_termux_version_forces_native_prompt() {
  local res
  res="$(unset DOTFILES_PROMPT; TERMUX_VERSION=0.118 _dotfiles_detect_prompt)"
  assert_eq "native" "$res"
}

test_mobile_proot_forces_native_prompt() {
  local res
  res="$(unset DOTFILES_PROMPT; PROOT_TMP_DIR=/tmp/proot _dotfiles_detect_prompt)"
  assert_eq "native" "$res"
}

test_prompt_preference_file_selected_when_not_mobile() {
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$XDG_CONFIG_HOME/dotfiles"
  print "native" > "$XDG_CONFIG_HOME/dotfiles/prompt"

  local res
  res="$(unset DOTFILES_PROMPT SSH_MOBILE LC_TERMINAL TERM_PROGRAM TERMUX_VERSION PROOT_TMP_DIR; _dotfiles_detect_prompt)"
  assert_eq "native" "$res"
}

test_mobile_detection_takes_precedence_over_preference_file() {
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$XDG_CONFIG_HOME/dotfiles"
  print "spaceship" > "$XDG_CONFIG_HOME/dotfiles/prompt"

  local res
  res="$(unset DOTFILES_PROMPT; SSH_MOBILE=1 _dotfiles_detect_prompt)"
  assert_eq "native" "$res"
}

test_env_override_takes_precedence_over_mobile_detection() {
  local res
  res="$(DOTFILES_PROMPT=spaceship SSH_MOBILE=1 _dotfiles_detect_prompt)"
  assert_eq "spaceship" "$res"
}
