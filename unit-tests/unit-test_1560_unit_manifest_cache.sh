#!/bin/sh
# Unit test: manifest_get_from_file and manifest_subprojects read the manifest
# Coverage: manifest_get_from_file, manifest_subprojects_from_file

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Create a small .gitnest file.
cat >.gitnest <<'MNF'
# git-nest manifest

[project]
version=1

[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=0123456789abcdef0123456789abcdef01234567
MNF

# manifest_get_from_file: reads a key from a specific manifest file by path.
assert_eq "$(manifest_get_from_file '.gitnest' 'project' 'version')" "1" "version from file"
assert_eq "$(manifest_get_from_file '.gitnest' 'subproject \"libs/foo\"' 'repo')" "https://example.invalid/foo.git" "repo from file"
assert_eq "$(manifest_get_from_file '.gitnest' 'subproject \"libs/foo\"' 'target_branch')" "main" "target_branch from file"

# manifest_subprojects_from_file: extracts paths from section headers.
_subprojs=$(manifest_subprojects_from_file '.gitnest')
assert_eq "$_subprojs" "libs/foo" "subproject path from file"

printf 'All tests passed.\n'
