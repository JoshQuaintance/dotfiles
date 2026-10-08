# _dot_history_filter (zsh/.zshrc): secret-looking assignments stay out of $HISTFILE

source <(sed -n '/^_dot_history_filter() {/,/^}/p' "$DOTFILES_DIR/zsh/.zshrc")

test_secret_assignments_are_not_saved() {
  local cmd
  for cmd in 'export GITHUB_TOKEN=ghp_abc' 'API_KEY=x curl example.com' 'mysql --password=hunter2' 'db_secret=abc ./run'; do
    _dot_history_filter "$cmd"
    assert_eq 2 $? "$cmd"
  done
}

test_ordinary_commands_are_saved() {
  local cmd
  for cmd in 'git commit -m "fix token parsing"' 'echo secret' 'ls -la' 'TOKEN= foo'; do
    _dot_history_filter "$cmd"
    assert_eq 0 $? "$cmd"
  done
}
