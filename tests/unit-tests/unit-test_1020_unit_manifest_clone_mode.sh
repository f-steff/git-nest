#!/bin/sh
# Unit test: validate_clone_mode accepts valid modes and rejects invalid ones
# Coverage: validate_clone_mode, validate_positive_integer

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# validate_clone_mode: valid modes are empty, full, partial, shallow.
assert_ok "empty clone mode is valid" -- validate_clone_mode "" "test context"
assert_ok "full clone mode is valid" -- validate_clone_mode "full" "test context"
assert_ok "partial clone mode is valid" -- validate_clone_mode "partial" "test context"
assert_ok "shallow clone mode is valid" -- validate_clone_mode "shallow" "test context"

# validate_clone_mode: invalid modes must abort with an error.
assert_fail "invalid clone mode is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    validate_clone_mode "invalid" "test context"
' sh "$REPO_ROOT"

# validate_positive_integer: valid positive integers must pass.
assert_ok "positive integer 1 is valid" -- validate_positive_integer "1" "test"
assert_ok "positive integer 42 is valid" -- validate_positive_integer "42" "test"
assert_ok "positive integer 999 is valid" -- validate_positive_integer "999" "test"

# validate_positive_integer: non-numeric, empty, and zero must fail.
assert_fail "zero is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    validate_positive_integer "0" "test"
' sh "$REPO_ROOT"
assert_fail "non-numeric is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    validate_positive_integer "abc" "test"
' sh "$REPO_ROOT"
assert_fail "empty string is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    validate_positive_integer "" "test"
' sh "$REPO_ROOT"

printf 'All tests passed.\n'
