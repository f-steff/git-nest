#!/bin/sh
# Unit test: resolve_commit with arg-differentiated mock
# Coverage: resolve_commit, resolve_head_commit

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# resolve_commit: resolves a ref to a commit SHA via git rev-parse.
mock_git_response "rev-parse" "--verify" "HEAD^{commit}" "abc123def456"
assert_eq "$(resolve_commit "/fake/repo" "HEAD" "test-context")" "abc123def456" "HEAD resolved"

# resolve_head_commit calls resolve_commit with HEAD.
assert_eq "$(resolve_head_commit "/fake/repo" "test-context")" "abc123def456" "HEAD commit resolved"

printf 'All tests passed.\n'
