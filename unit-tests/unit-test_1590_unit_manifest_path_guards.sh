#!/bin/sh
# Unit test: assert_safe_project_path and assert_no_case_collision
# Coverage: assert_safe_project_path, assert_no_case_collision, path_is_manifest_subproject_or_child

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# assert_safe_project_path: passes safe paths silently, aborts on unsafe ones.
assert_ok "safe path passes" -- assert_safe_project_path "libs/foo"
assert_fail "empty path fails" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    assert_safe_project_path ""
' sh "$REPO_ROOT"
assert_fail "absolute path fails" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    assert_safe_project_path "/absolute"
' sh "$REPO_ROOT"

# assert_no_case_collision: needs manifest entries. Create one.
cat >.gitnest <<'MNF'
[project]
version=1
[subproject "Libs/Foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=0123456789abcdef0123456789abcdef01234567
MNF
manifest_load_cache

# A path with different case but same letters collides on case-insensitive fs.
assert_fail "case collision detected" -- sh -c '
    cd "$1"
    MANIFEST_FILE=.gitnest
    . "$2/bin/lib/git-nest-manifest.sh" 2>/dev/null
    manifest_load_cache
    assert_no_case_collision "libs/foo"
' sh "$UNIT_TEST_TEMP" "$REPO_ROOT"

# A completely different path does not collide.
assert_ok "different path is safe" -- assert_no_case_collision "other/path"

printf 'All tests passed.\n'
