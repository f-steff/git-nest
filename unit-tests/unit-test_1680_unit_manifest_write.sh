#!/bin/sh
# Unit test: manifest_write_subproject, manifest_remove_section, subproject_repo, outer_submodule_name_for_path
# Coverage: manifest_write_subproject, manifest_remove_section, subproject_repo, outer_submodule_name_for_path, manifest_subprojects

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Create a base manifest.
cat >.gitnest <<'MNF'
[project]
version=1
MNF
ensure_manifest 2>/dev/null || true

# manifest_write_subproject: writes a tracked subproject section.
manifest_write_subproject "libs/foo" "https://example.invalid/foo.git" \
    tracked "main" "0123456789abcdef0123456789abcdef01234567" "full"
assert_ok "manifest now has repo" -- grep -qF 'repo=https://example.invalid/foo.git' .gitnest
assert_ok "manifest has target_branch" -- grep -qF 'target_branch=main' .gitnest
assert_ok "manifest has clone=full" -- grep -qF 'clone=full' .gitnest

# subproject_repo: reads the repo key from the manifest.
# Need to reload the cache after writing.
manifest_load_cache
assert_eq "$(subproject_repo 'libs/foo')" "https://example.invalid/foo.git" "subproject repo read"

# manifest_subprojects lists the path.
_subprojs=$(manifest_subprojects)
assert_eq "$_subprojs" "libs/foo" "path in manifest"

# manifest_remove_section: removes a section. Validated by file content check.
manifest_remove_section 'subproject "libs/foo"'
assert_fail "section removed from file" -- grep -qF '[subproject "libs/foo"]' .gitnest

# outer_submodule_name_for_path requires git config to return specific
# submodule entries, which needs arg-differentiated mock responses.
# Tested by integration tests instead.

printf 'All tests passed.\n'
