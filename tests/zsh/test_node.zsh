# _find_package_json / _extract_pkg_scripts / npmr

test_find_package_json_in_current_dir() {
  print "{}" > package.json
  local found
  found="$(_find_package_json)"
  assert_eq "${PWD:A}/package.json" "${found:A}"
}

test_find_package_json_in_ancestor_dir() {
  print "{}" > package.json
  mkdir -p src/components/button
  cd src/components/button
  local found
  found="$(_find_package_json)"
  assert_eq "${HOME:A}/package.json" "${found:A}"
}

test_find_package_json_outside_node_project_fails() {
  local found rc=0
  found="$(_find_package_json 2>/dev/null)" || rc=$?
  assert_eq 1 $rc
}

test_extract_pkg_scripts_parses_json_entries() {
  cat > package.json << "JSON"
{
  "name": "sample-project",
  "scripts": {
    "build": "vite build",
    "test": "vitest run",
    "lint": "eslint ."
  }
}
JSON
  local scripts
  scripts="$(_extract_pkg_scripts "$PWD/package.json")"
  assert_contains "$scripts" "build	vite build"
  assert_contains "$scripts" "test	vitest run"
  assert_contains "$scripts" "lint	eslint ."
}

test_npmr_without_package_json_fails() {
  local out rc=0
  out="$(npmr 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "Cannot find a package.json file"
}

test_pkg_script_select_without_fzf_lists_scripts() {
  cat > package.json << "JSON"
{
  "scripts": {
    "build": "vite build",
    "check": "tsc --noEmit"
  }
}
JSON
  local out rc=0
  out="$(PATH="/usr/bin:/bin" _pkg_script_select npm 2>&1)" || rc=$?
  assert_eq 0 $rc
  assert_contains "$out" "Available scripts in"
  assert_contains "$out" "build"

  bunr --help >/dev/null || fail "bunr --help failed"
  pnpmr --help >/dev/null || fail "pnpmr --help failed"
}
