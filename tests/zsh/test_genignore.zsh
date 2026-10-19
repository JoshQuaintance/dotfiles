# genignore idempotent block updates

test_genignore_creates_delimited_block() {
  git init >/dev/null 2>&1
  touch package.json
  "$DOTFILES_DIR/bin/genignore" >/dev/null 2>&1 || fail "genignore failed"
  assert_file .gitignore
  local content
  content="$(<.gitignore)"
  assert_contains "$content" "# >>> genignore start >>>"
  assert_contains "$content" "# <<< genignore end <<<"
  assert_contains "$content" "node_modules/"
}

test_genignore_is_idempotent_and_preserves_custom_lines() {
  git init >/dev/null 2>&1
  cat > .gitignore << 'EOF'
# My Custom Rule
*.local.secret

# >>> genignore start >>>
old_garbage/
# <<< genignore end <<<

# Another Custom Rule
custom_dir/
EOF

  "$DOTFILES_DIR/bin/genignore" macos,vim >/dev/null 2>&1 || fail "genignore failed"

  local content
  content="$(<.gitignore)"
  local start_count end_count
  start_count=$(grep -c "^# >>> genignore start >>>" .gitignore)
  end_count=$(grep -c "^# <<< genignore end <<<" .gitignore)

  assert_eq "1" "$start_count"
  assert_eq "1" "$end_count"
  assert_contains "$content" "*.local.secret"
  assert_contains "$content" "custom_dir/"
  if grep -q "old_garbage/" .gitignore; then
    fail "old managed block was not replaced"
  fi
}
