# take / up

test_take_creates_nested_dir_and_enters_it() {
  take a/b/c
  assert_eq "${HOME:A}/a/b/c" "${PWD:A}"
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
