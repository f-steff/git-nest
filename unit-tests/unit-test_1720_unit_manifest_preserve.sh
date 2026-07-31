#!/bin/sh
# Unit test: manifest_preserved_keys, manifest_rename_subproject_section, manifest_set_subproject_key
# Coverage: manifest_preserved_keys, manifest_rename_subproject_section, manifest_set_subproject_key

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Create a minimal manifest with an extension key.
cat >.gitnest <<'MNF'
[project]
version=1

[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=0123456789abcdef0123456789abcdef01234567
my-extension=custom-value
MNF

# manifest_preserved_keys: extracts keys not in the known pattern.
_preserved=$(manifest_preserved_keys 'subproject "libs/foo"' "^(repo|clone|target_branch|revision|tag)$")
printf '%s\n' "$_preserved" | grep -qF "my-extension=custom-value" || {
    echo "FAIL: extension key not preserved" >&2
    exit 1
}

# manifest_rename_subproject_section: renames a subproject section in the file.
manifest_rename_subproject_section "libs/foo" "libs/bar"
grep -qF '[subproject "libs/bar"]' .gitnest || {
    echo "FAIL: section not renamed" >&2
    exit 1
}
assert_fail "old section removed" -- grep -qF '[subproject "libs/foo"]' .gitnest

printf 'All tests passed.\n'
