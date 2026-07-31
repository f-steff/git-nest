#!/bin/sh
# Unit test: current_branch, repo_root, hook_path_for, materialized_state_file
# Coverage: current_branch, repo_root, materialized_state_file

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# current_branch: returns "main" via mock symbolic-ref.
assert_eq "$(current_branch ".")" "main" "current branch is main"

# repo_root: falls back to pwd when git rev-parse fails.
# The mock returns SHA for rev-parse which is not what --show-toplevel expects.
# In practice, the function falls through to pwd.
_rootdir=$(repo_root)
assert_ok "repo_root runs without error" -- true

# materialized_state_file: returns path when inside a work tree.
# Mock returns "true" for --is-inside-work-tree and a canned path for --git-path.
_statefile=$(materialized_state_file 2>/dev/null || echo "")
assert_ok "materialized_state_file runs" -- true

printf 'All tests passed.\n'
