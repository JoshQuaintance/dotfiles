# take / up

test_take_creates_nested_dir_and_enters_it() {
  take a/b/c
  assert_eq "${HOME:A}/a/b/c" "${PWD:A}"
}

test_take_with_file_extension_creates_file_and_enters_dir() {
  take src/components/Button.tsx
  assert_eq "${HOME:A}/src/components" "${PWD:A}"
  assert_file "Button.tsx"
}

test_take_without_extension_creates_dir() {
  take my-folder
  assert_eq "${HOME:A}/my-folder" "${PWD:A}"
}

test_take_with_trailing_slash_creates_dir() {
  take site.com/
  assert_eq "${HOME:A}/site.com" "${PWD:A}"
}

test_groot_outside_git_repo_fails() {
  local out
  out="$(groot 2>&1)" || local rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "Not inside a git repository"
}

test_up_by_count() {
  mkdir -p x/y/z && cd x/y/z
  up 2 >/dev/null
  assert_eq "${HOME:A}/x" "${PWD:A}"
}

test_up_by_ancestor_name() {
  mkdir -p project/src/deep && cd project/src/deep
  up project >/dev/null
  assert_eq "${HOME:A}/project" "${PWD:A}"
}

test_up_defaults_to_one_level() {
  mkdir -p p/q/r && cd p/q/r
  up >/dev/null
  assert_eq "${HOME:A}/p/q" "${PWD:A}"
}

test_up_by_substring_ancestor() {
  mkdir -p project-analytics/src/utils && cd project-analytics/src/utils
  up analytics >/dev/null
  assert_eq "${HOME:A}/project-analytics" "${PWD:A}"
}

test_up_nonexistent_ancestor_fails_and_preserves_pwd() {
  mkdir -p p/q/r && cd p/q/r
  local out rc=0
  out="$(up nonexistent 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "No ancestor directory matching"
  assert_eq "${HOME:A}/p/q/r" "${PWD:A}"
}

test_up_help_flag_returns_zero() {
  local out rc=0
  out="$(up --help)" || rc=$?
  assert_eq 0 $rc
  assert_contains "$out" "Usage: up"
}

test_gmain_jumps_to_primary_repo_root_from_worktree() {
  git_test init -q main_repo
  cd main_repo
  git_test commit -q --allow-empty -m "init"
  git_test worktree add -q ../wt-feature -b wt-feature
  cd ../wt-feature
  mkdir -p deep/nested/dir && cd deep/nested/dir

  gmain >/dev/null || fail "gmain failed"
  assert_eq "${HOME:A}/main_repo" "${PWD:A}"
}

test_d_index_out_of_range_fails() {
  local out rc=0
  out="$(d 99 2>&1)" || rc=$?
  assert_eq 1 $rc
  assert_contains "$out" "out of range"
}

test_proj_discovers_repos_and_jumps_by_exact_name() {
  export DOTFILES_PROJECTS_DIR="$HOME/Codes"
  mkdir -p "$DOTFILES_PROJECTS_DIR/sales/ui" "$DOTFILES_PROJECTS_DIR/sales/service"
  git_test init -q "$DOTFILES_PROJECTS_DIR/alpha-service"
  git_test -C "$DOTFILES_PROJECTS_DIR/alpha-service" checkout -q -b feat/login
  git_test init -q "$DOTFILES_PROJECTS_DIR/sales/ui/develop"
  git_test -C "$DOTFILES_PROJECTS_DIR/sales/ui/develop" checkout -q -b develop
  git_test init -q "$DOTFILES_PROJECTS_DIR/sales/service/develop"
  git_test -C "$DOTFILES_PROJECTS_DIR/sales/service/develop" checkout -q -b develop

  local list_out
  list_out="$(proj -l)"
  assert_contains "$list_out" $'alpha-service\tfeat/login\t'
  assert_contains "$list_out" $'sales/ui/develop\tdevelop\t'
  assert_contains "$list_out" $'sales/service/develop\tdevelop\t'

  proj alpha-service
  assert_eq "${DOTFILES_PROJECTS_DIR:A}/alpha-service" "${PWD:A}"

  proj sales/ui/develop
  assert_eq "${DOTFILES_PROJECTS_DIR:A}/sales/ui/develop" "${PWD:A}"
}

test_dotenv_loads_without_eval_and_unloads_cleanly() {
  cat > .env <<'EOF'
# Comment line
SIMPLE_KEY=hello_world # inline comment
export EXPORTED_KEY="quoted \"value\" with spaces" # trailing comment
SINGLE_QUOTED='$(echo should_not_execute)'
CRLF_KEY=win_value
EOF
  printf "CRLF_KEY=win_val\r\n" >> .env

  dotenv .env >/dev/null
  assert_eq "hello_world" "$SIMPLE_KEY"
  assert_eq 'quoted "value" with spaces' "$EXPORTED_KEY"
  assert_eq '$(echo should_not_execute)' "$SINGLE_QUOTED"
  assert_eq "win_val" "$CRLF_KEY"

  local list_out
  list_out="$(dotenv -l)"
  assert_contains "$list_out" "SIMPLE_KEY=hello_world"
  assert_contains "$list_out" "SINGLE_QUOTED=\$(echo should_not_execute)"

  dotenv -u >/dev/null
  assert_eq "" "${SIMPLE_KEY:-}"
  assert_eq "" "${EXPORTED_KEY:-}"
  assert_eq "" "${SINGLE_QUOTED:-}"
  assert_eq "" "${CRLF_KEY:-}"
}

test_fpkg_lists_brew_and_mise_packages() {
  mkdir -p "$HOME/pkg_stubs"
  print -r -- '#!/bin/sh
if [ "$2" = "--formula" ]; then
  printf "ripgrep 15.2.0\nfd 10.5.0\n"
elif [ "$2" = "--cask" ]; then
  printf "ghostty 1.2.0\n"
fi' > "$HOME/pkg_stubs/brew"
  print -r -- '#!/bin/sh
printf "node 24.21.0 ~/.config/mise/config.toml 24\n"' > "$HOME/pkg_stubs/mise"
  chmod +x "$HOME/pkg_stubs/brew" "$HOME/pkg_stubs/mise"

  local out
  out="$(PATH="$HOME/pkg_stubs:$PATH" fpkg -l)"
  assert_contains "$out" $'brew\tripgrep\t15.2.0'
  assert_contains "$out" $'cask\tghostty\t1.2.0'
  assert_contains "$out" $'mise\tnode\t24.21.0'
}

test_wpath_and_wcd_translate_windows_and_uri_paths() {
  assert_eq "/mnt/c/Users/josh/Desktop" "$(wpath -u 'C:\Users\josh\Desktop')"
  assert_eq 'C:\Users\josh\Desktop' "$(wpath -w '/mnt/c/Users/josh/Desktop')"

  mkdir -p "$HOME/win_target"
  touch "$HOME/win_target/app.ts"
  wcd "file://$HOME/win_target/app.ts"
  assert_eq "${HOME:A}/win_target" "${PWD:A}"
}

test_snip_lists_and_adds_custom_snippets() {
  local out
  out="$(snip -l)"
  assert_contains "$out" "git/undo-commit"
  assert_contains "$out" "ssh/port-forward-local"

  snip -a "custom/hello" "echo '<greeting>'" "Print greeting" >/dev/null
  assert_contains "$(snip -l custom/hello)" $'custom/hello\techo \'<greeting>\'\tPrint greeting'
}

test_decode_handles_jwt_epoch_url_and_base64() {
  # 1. JWT ({"alg":"HS256"} . {"sub":"1234567890","name":"Josh"})
  local jwt="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Ikpvc2gifQ.sig"
  local jwt_out
  jwt_out="$(decode "$jwt")"
  assert_contains "$jwt_out" '"alg": "HS256"'
  assert_contains "$jwt_out" '"name": "Josh"'

  # 2. Epoch timestamp
  local ep_out
  ep_out="$(decode 1700000000)"
  assert_contains "$ep_out" "2023-11-14"

  # 3. URL & query string
  local url_out
  url_out="$(decode 'https://example.com/search?q=hello%20world&lang=en')"
  assert_contains "$url_out" "hello world"
  assert_contains "$url_out" "lang"

  # 4. Base64
  local b64_out
  b64_out="$(decode 'aGVsbG8tZGVjb2Rl')"
  assert_eq "hello-decode" "$b64_out"

  # 5. UUIDv7, Hex, and HTML entities
  assert_contains "$(decode '018f4a7c-8e10-7000-8000-000000000001' | strip_ansi)" "UUID (v7)"
  assert_contains "$(decode '0x68656c6c6f' | strip_ansi)" "hello"
  assert_contains "$(decode '&lt;span&gt;ok&amp;good&lt;/span&gt;' | strip_ansi)" "<span>ok&good</span>"
}

test_port_fpkg_action_and_conf_candidates() {
  mkdir -p "$HOME/proc_stubs"
  cat <<'EOF' > "$HOME/proc_stubs/lsof"
#!/usr/bin/env bash
if [[ "$*" == *"-t -i :9999"* ]]; then
  echo ""
elif [[ "$*" == *"-i :8080"* ]]; then
  echo "node 12345 user 20u IPv4 0x1 0t0 TCP *:8080 (LISTEN)"
fi
EOF
  chmod +x "$HOME/proc_stubs/lsof"

  local port_info
  port_info="$(PATH="$HOME/proc_stubs:$PATH" port 8080)"
  assert_contains "$port_info" "12345"

  local kill_rc=0
  PATH="$HOME/proc_stubs:$PATH" port -k 9999 >/dev/null 2>&1 || kill_rc=$?
  assert_eq 1 $kill_rc

  local conf_out
  conf_out="$(_conf_candidates)"
  assert_contains "$conf_out" $'functions\t'
  assert_contains "$conf_out" $'ghostty\t'
}

test_fsize_fknown_and_termtest() {
  mkdir -p "$HOME/sz_test/sub"
  printf "hello world\n" > "$HOME/sz_test/file.txt"
  local sz_out
  sz_out="$(fsize -l "$HOME/sz_test")"
  assert_contains "$sz_out" "file.txt"

  mkdir -p "$HOME/.ssh"
  printf "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n" > "$HOME/.ssh/known_hosts"
  local kh_out
  kh_out="$(fknown -l)"
  assert_contains "$kh_out" $'known_host\tgithub.com\tssh-ed25519'

  local tt_out
  tt_out="$(termtest)"
  assert_contains "$tt_out" "Truecolor RGB Gradient"
  assert_contains "$tt_out" "Catppuccin Mocha Swatches"
}
