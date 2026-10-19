setopt ALIASES
source "$DOTFILES_DIR/zsh/.aliases"

test_core_aliases_defined() {
  assert_eq "dottest" "${aliases[.test]}"
  assert_eq "reload" "${aliases[sz]}"
  assert_eq "exec zsh -l" "${aliases[reload]}"
  assert_eq "toggle-autols" "${aliases[als]}"
  assert_eq "genignore" "${aliases[gi]}"
  assert_eq "trash" "${aliases[del]}"
}

test_pyactivate_in_place_eval_activates_dot_venv() {
  mkdir -p .venv/bin
  cat > .venv/bin/activate << "ACTIVATE"
export VIRTUAL_ENV="/custom/dot_venv"
ACTIVATE

  eval "${aliases[pyactivate]}"
  assert_eq "/custom/dot_venv" "$VIRTUAL_ENV"
}

test_pyactivate_in_place_eval_activates_standard_venv() {
  mkdir -p venv/bin
  cat > venv/bin/activate << "ACTIVATE"
export VIRTUAL_ENV="/custom/standard_venv"
ACTIVATE

  eval "${aliases[pyactivate]}"
  assert_eq "/custom/standard_venv" "$VIRTUAL_ENV"
}

test_pyactivate_missing_venv_prints_message() {
  local out
  out="$(eval "${aliases[pyactivate]}")"
  assert_contains "$out" "No .venv or venv found in current directory"
}

test_localip_alias_defined_and_valid_syntax() {
  local alias_cmd="${aliases[localip]}"
  [[ -n "$alias_cmd" ]] || fail "localip alias is not defined"

  zsh -n -c "$alias_cmd" || fail "localip alias syntax error"

  local ip_out
  ip_out="$(eval "$alias_cmd" 2>/dev/null)"
  if [ -n "$ip_out" ]; then
    [[ "$ip_out" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid ip format: $ip_out"
  fi
}
