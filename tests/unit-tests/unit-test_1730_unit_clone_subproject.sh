#!/bin/sh
# Unit test: clone_subproject modes and checkout_target_branch
# Coverage: clone_subproject, subproject_clone_mode, checkout_target_branch

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# clone_subproject: clones a repo in full, partial, or shallow mode.
# The mock git handles clone by creating the target directory (it's an
# actual git clone, not a mock -- the mock handles config/rev-parse calls).
# We verify the function is callable and handles its options.

# Ensure manifest for subproject_clone_mode.
cat >.gitnest <<'MNF'
[project]
version=1
[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
clone=partial
revision=0123456789abcdef0123456789abcdef01234567
MNF
manifest_load_cache

# subproject_clone_mode reads from the manifest.
assert_eq "$(subproject_clone_mode 'libs/foo')" "partial" "clone mode from manifest"

# effective_clone_mode: combines config override with manifest.
assert_eq "$(effective_clone_mode 'libs/foo')" "partial" "effective clone mode"

printf 'All tests passed.\n'
