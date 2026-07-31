#!/bin/sh
# Unit test: repo_is_partial_clone with arg-differentiated mock
# Coverage: repo_is_partial_clone

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# repo_is_partial_clone: needs promisor=true AND filter=blob:none.
# Use arg-differentiated mock to set each config key separately.

# Case 1: both match -> partial clone detected
mock_git_response "config" "--get" "remote.origin.promisor" "true"
mock_git_response "config" "--get" "remote.origin.partialclonefilter" "blob:none"
assert_ok "partial clone detected" -- repo_is_partial_clone "/any/path"

# Case 2: promisor false -> not partial
mock_git_response "config" "--get" "remote.origin.promisor" ""
mock_git_response "config" "--get" "remote.origin.partialclonefilter" "blob:none"
assert_fail "promisor false means not partial" -- repo_is_partial_clone "/any/path"

# Case 3: filter not blob:none -> not partial
mock_git_response "config" "--get" "remote.origin.promisor" "true"
mock_git_response "config" "--get" "remote.origin.partialclonefilter" "other"
assert_fail "wrong filter means not partial" -- repo_is_partial_clone "/any/path"

printf 'All tests passed.\n'
