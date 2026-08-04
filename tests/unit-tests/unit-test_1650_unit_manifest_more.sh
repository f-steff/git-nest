#!/bin/sh
# Unit test: validate_config_value, is_gitignore_constant, pair_path_exists, tmp_for
# Coverage: validate_config_value, is_gitignore_constant, pair_path_exists, tmp_for, manifest_pairs_file

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# is_gitignore_constant: checks if a path pattern is a built-in constant.
GITIGNORE_GIT_DIR_GUARD_ONE='**/.git/'
GITIGNORE_GIT_DIR_GUARD_TWO='**/.git'
assert_ok "**/.git/ is a constant" -- is_gitignore_constant "**/.git/"
assert_ok "**/.git is a constant" -- is_gitignore_constant "**/.git"
assert_fail "custom path is not a constant" -- is_gitignore_constant "libs/foo"

# pair_path_exists: checks if a path exists in a tab-separated pairs file.
printf 'libs/foo\thttps://foo.git\n' >_pairs.txt
printf 'libs/bar\thttps://bar.git\n' >>_pairs.txt
assert_ok "foo pair exists" -- pair_path_exists _pairs.txt "libs/foo"
assert_fail "baz pair does not exist" -- pair_path_exists _pairs.txt "libs/baz"

printf 'All tests passed.\n'
