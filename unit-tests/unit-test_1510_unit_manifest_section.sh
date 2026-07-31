#!/bin/sh
# Unit test: manifest_varname, manifest_section_kind, subproject_section
# Coverage: manifest_varname, manifest_section_kind, subproject_section

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# subproject_section: formats the section header for .gitnest.
assert_eq "$(subproject_section 'libs/foo')" 'subproject "libs/foo"' "section header formatted"
assert_eq "$(subproject_section 'a/b/c')" 'subproject "a/b/c"' "deep path"

# manifest_section_kind: classifies section names.
assert_eq "$(manifest_section_kind 'project')" "project" "project section"
assert_eq "$(manifest_section_kind 'subproject "libs/foo"')" "subproject" "subproject section"
assert_eq "$(manifest_section_kind 'unknown')" "unknown" "unknown section"

# manifest_varname: computes a hash-based variable name.
# For the project section, it uses the key name directly.
_pv=$(manifest_varname 'project' 'version')
assert_eq "$_pv" "_mnf_project_version" "project version var"

# For a subproject section, it hashes the path with cksum.
_spv=$(manifest_varname 'subproject "libs/foo"' 'repo')
printf '%s\n' "$_spv" | grep -q '^_mnf_sp_' || {
    echo "FAIL: subproject var name does not start with _mnf_sp_" >&2
    exit 1
}
printf '%s\n' "$_spv" | grep -q '_repo$' || {
    echo "FAIL: subproject var name does not end with _repo" >&2
    exit 1
}

# The same path always produces the same hash.
_spv2=$(manifest_varname 'subproject "libs/foo"' 'repo')
assert_eq "$_spv" "$_spv2" "same path produces same hash"

printf 'All tests passed.\n'
