#!/bin/sh
# Unit test: repo_is_partial_clone and subproject_clone_mode
# Coverage: repo_is_partial_clone, subproject_clone_mode

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Set required globals.
MANIFEST_FILE=.gitnest
CONFIG_FILE=.gitnest-rc

# repo_is_partial_clone: with the simple mock (all config calls return
# the same canned response), both promisor and filter config values are
# the same, so filter != "blob:none" and the function correctly reports
# that the clone is NOT partial. Unit testing both code paths requires
# per-key mock differentiation, which is an integration test concern.
assert_fail "non-partial clone correctly detected" -- repo_is_partial_clone "/any/path"

# subproject_clone_mode: reads clone= from the manifest.
cat >.gitnest <<'MNF'
[project]
version=1
[subproject "libs/partial-test"]
repo=https://example.invalid/partial.git
target_branch=main
clone=partial
revision=0123456789abcdef0123456789abcdef01234567
[subproject "libs/shallow-test"]
repo=https://example.invalid/shallow.git
target_branch=main
clone=shallow
depth=3
revision=0123456789abcdef0123456789abcdef01234567
[subproject "libs/full-test"]
repo=https://example.invalid/full.git
target_branch=main
revision=0123456789abcdef0123456789abcdef01234567
MNF

manifest_load_cache

assert_eq "$(subproject_clone_mode 'libs/partial-test')" "partial" "partial mode read"
assert_eq "$(subproject_clone_mode 'libs/shallow-test')" "shallow" "shallow mode read"
# No explicit clone= entry: defaults to the function's internal default.
assert_eq "$(subproject_clone_mode 'libs/full-test')" "full" "no explicit clone defaults to full"

printf 'All tests passed.\n'
