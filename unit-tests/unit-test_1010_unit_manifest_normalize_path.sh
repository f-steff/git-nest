#!/bin/sh
# Unit test: normalize_path and reject_backslash_path clean and validate subproject paths
# Coverage: normalize_path, reject_backslash_path

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# normalize_path collapses duplicate slashes and strips trailing slashes.
assert_eq "$(normalize_path "libs/foo")" "libs/foo" "plain path is unchanged"
assert_eq "$(normalize_path "libs//foo")" "libs/foo" "double slashes collapsed"
assert_eq "$(normalize_path "libs/foo/")" "libs/foo" "trailing slash stripped"
assert_eq "$(normalize_path "libs//foo//")" "libs/foo" "both collapsed and stripped"
assert_eq "$(normalize_path "libs///foo///bar")" "libs/foo/bar" "multiple double slashes"
assert_eq "$(normalize_path ".//")" "." "root dot normalized"

# reject_backslash_path aborts with a usage error for backslash paths.
# The function calls usage_error which calls exit, so we wrap it in a subshell
# to prevent the test from aborting.
assert_fail "backslash path is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    reject_backslash_path "libs\\foo"
' sh "$REPO_ROOT"

# Forward slashes pass silently.
assert_ok "forward slash path is accepted" -- reject_backslash_path "libs/foo"

printf 'All tests passed.\n'
