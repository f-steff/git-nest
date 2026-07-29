#!/bin/sh
# Test: manifest schema validation accepts valid and rejects invalid manifests

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_manifest_schema

test_step "Exercise contract manifest schema" "This test verifies the documented contract manifest schema behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_manifest_schema)

valid="$root/valid"
make_repo "$valid"
cd "$valid"
"$GIT_NEST" init >/dev/null
assert_file_contains .gitnest "version=1"
"$GIT_NEST" status >/dev/null

case_dir() {
    name=$1
    body=$2
    dir="$root/$name"
    make_repo "$dir"
    cd "$dir"
    printf '%s\n' "$body" >.gitnest
}

case_dir missing_version '[project]'
if "$GIT_NEST" status >out 2>err; then
    echo "missing version should fail" >&2
    exit 1
fi
assert_file_contains err "missing manifest schema version"

case_dir wrong_version '[project]
version=2'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "unsupported manifest schema version 2"

case_dir duplicate_section '[project]
version=1
[project]
version=1'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "duplicate section"

case_dir duplicate_subproject_section '[project]
version=1
[subproject "libs/foo"]
repo=file:///tmp/foo.git
[subproject "libs/foo"]
repo=file:///tmp/foo.git'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "duplicate section"

case_dir duplicate_key '[project]
version=1
version=1'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "duplicate key"

case_dir unknown_key '[project]
version=1
unknown=value'
"$GIT_NEST" status >/dev/null

case_dir unknown_subproject_key '[project]
version=1
[subproject "libs/foo"]
repo=file:///tmp/foo.git
unexpected=value'
"$GIT_NEST" status >/dev/null

case_dir unknown_section '[project]
version=1
[extension "tool"]
owner=value'
"$GIT_NEST" status >/dev/null

case_dir malformed_section '[project]
version=1
[subproject libs/foo]'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "malformed subproject section"

case_dir missing_repo '[project]
version=1
[subproject "libs/foo"]
target_branch=main'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "missing repo"

case_dir invalid_clone '[project]
version=1
[subproject "libs/foo"]
repo=file:///tmp/foo.git
clone=shallow'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "invalid clone mode"

case_dir obsolete_pending '[project]
version=1
[subproject "libs/foo"]
repo=file:///tmp/foo.git
pending_branch=TOPIC-1
target_branch=main
base_revision=abc123'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "pending_branch is no longer supported"
assert_file_contains err "base_revision is no longer supported"

case_dir tag_without_revision '[project]
version=1
[subproject "libs/foo"]
repo=file:///tmp/foo.git
tag=v1.0.0'
assert_exit_code 3 "$GIT_NEST" status >/dev/null 2>err
assert_file_contains err "tag requires revision"

describe_result "The contract manifest schema behavior matched the expected command output and repository state."
