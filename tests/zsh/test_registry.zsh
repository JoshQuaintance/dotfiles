# Function registry: everything listed in DOTFILES_FUNCTIONS exists and doesn't hide a real command.

test_registered_functions_are_defined() {
  local fn
  for fn in $DOTFILES_FUNCTIONS; do
    (( $+functions[$fn] )) || fail "registered but not defined: $fn"
  done
}

test_functions_do_not_shadow_commands() {
  # Deliberate wrappers: tree (eza tree view), open (Linux/WSL opener; Debian's `open` is openvt),
  # dotenv (in-shell .env loader; external dotenv CLI cannot export into parent shell)
  local -a allowed=(tree open dotenv)
  local fn bin
  for fn in $DOTFILES_FUNCTIONS; do
    (( ${allowed[(I)$fn]} )) && continue
    bin="$(whence -p "$fn")" && fail "function '$fn' hides $bin (rename it, as paste -> clippaste)"
  done
  return 0
}

test_fjq_enumerates_json_paths() {
  command -v jq &>/dev/null || return 0
  local out
  out=$(printf '{"app":{"name":"dotfiles","tags":["zsh","nvim"]}}\n' | fjq)
  assert_contains "$out" ".app.name"
  assert_contains "$out" ".app.tags[0]"

  if command -v yq &>/dev/null; then
    local yml_out toml_out
    yml_out=$(fjq "$DOTFILES_DIR/config/lazygit/config.yml")
    assert_contains "$yml_out" ".gui.nerdFontsVersion"
    toml_out=$(fjq "$DOTFILES_DIR/config/atuin/config.toml")
    assert_contains "$toml_out" ".search_mode"
  fi
}

test_fa_includes_bin_tool_descriptions() {
  local out
  out=$(fa -p dotcheck)
  assert_contains "$out" "Check if dotfiles repository has upstream updates"
}
