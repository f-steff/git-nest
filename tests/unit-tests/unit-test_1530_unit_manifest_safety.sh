#!/bin/sh
# Unit test: safe_stale_path and nearby safety helpers
# Coverage: safe_stale_path

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# safe_stale_path: rejects dangerous paths that should never be deleted.
# Returns 0 (true) for safe relative paths, 1 (false) for unsafe ones.
assert_ok "simple path is safe" -- safe_stale_path "libs/foo"
assert_ok "deep path is safe" -- safe_stale_path "a/b/c/d"
assert_fail "empty path is unsafe" -- safe_stale_path ""
assert_fail "dot is unsafe" -- safe_stale_path "."
assert_fail "dot dot is unsafe" -- safe_stale_path ".."
assert_fail "absolute path is unsafe" -- safe_stale_path "/etc/passwd"
assert_fail "parent escape prefix is unsafe" -- safe_stale_path "../outside"
assert_fail "parent escape mid-path is unsafe" -- safe_stale_path "libs/../escape"
assert_fail "parent escape suffix is unsafe" -- safe_stale_path "libs/foo/.."
assert_fail "double slash is unsafe" -- safe_stale_path "libs//foo"
# safe_stale_path returns 0 (safe) for valid relative paths.

printf 'All tests passed.\n'
