# Function registry: everything listed in DOTFILES_FUNCTIONS exists and doesn't hide a real command.

test_registered_functions_are_defined() {
  local fn
  for fn in $DOTFILES_FUNCTIONS; do
    (( $+functions[$fn] )) || fail "registered but not defined: $fn"
  done
}

test_functions_do_not_shadow_commands() {
  # Deliberate wrappers: tree (eza tree view), open (Linux/WSL opener; Debian's `open` is openvt)
  local -a allowed=(tree open)
  local fn bin
  for fn in $DOTFILES_FUNCTIONS; do
    (( ${allowed[(I)$fn]} )) && continue
    bin="$(whence -p "$fn")" && fail "function '$fn' hides $bin (rename it, as paste -> clippaste)"
  done
  return 0
}
