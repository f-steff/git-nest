#!/bin/sh
# Unit test: path_is_relative_safe rejects absolute, parent-escape, and reserved paths
# Coverage: path_is_relative_safe

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Valid relative paths must pass.
# path_is_relative_safe returns 0 (true) for safe paths.
assert_ok "simple relative path is safe" -- path_is_relative_safe "libs/foo"
assert_ok "deep relative path is safe" -- path_is_relative_safe "a/b/c/d"
assert_ok "single directory is safe" -- path_is_relative_safe "src"
assert_ok "path with dot in name is safe" -- path_is_relative_safe "libs/foo.bar"

# Reserved names and unsafe patterns must be rejected.
# path_is_relative_safe returns 1 (false) for unsafe paths.
assert_fail "empty string is unsafe" -- path_is_relative_safe ""
assert_fail "absolute path is unsafe" -- path_is_relative_safe "/absolute/path"
assert_fail "parent escape is unsafe" -- path_is_relative_safe "../outside"
assert_fail "dot dot mid-path is unsafe" -- path_is_relative_safe "libs/../escape"
assert_fail "bare dot is unsafe" -- path_is_relative_safe "."
assert_fail "bare dot dot is unsafe" -- path_is_relative_safe ".."
assert_fail ".git is reserved" -- path_is_relative_safe ".git"
assert_fail ".gitnest is reserved" -- path_is_relative_safe ".gitnest"
assert_fail ".gitignore is reserved" -- path_is_relative_safe ".gitignore"
assert_fail ".gitattributes is reserved" -- path_is_relative_safe ".gitattributes"
assert_fail "path starting with .git/ is unsafe" -- path_is_relative_safe ".git/refs"
assert_fail "path ending with /.git is unsafe" -- path_is_relative_safe "libs/foo/.git"
assert_fail "Windows absolute path is unsafe" -- path_is_relative_safe "C:\\Users"
assert_fail ".gitnest.lock is reserved" -- path_is_relative_safe ".gitnest.lock"

printf 'All tests passed.\n'
