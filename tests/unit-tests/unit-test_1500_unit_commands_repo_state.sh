#!/bin/sh
# Unit test: repo_dirty, repo_has_dirty, remote_exists
# Coverage: repo_dirty, repo_has_dirty, remote_exists, repo_status_porcelain

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# repo_status_porcelain: calls git -C status --porcelain.
# The mock returns empty status output, so the directory appears clean.
mkdir -p libs/clean-repo
_clean=$(repo_status_porcelain "libs/clean-repo" "test context")
assert_eq "$_clean" "" "clean repo has no porcelain output"

# repo_has_dirty: returns nonzero when dirty, zero when clean.
# With an empty mock status, the repo appears clean.
set +e
repo_has_dirty "libs/clean-repo"
_rd_rc=$?
set -e
assert_eq "$_rd_rc" "1" "clean repo returns 1 (false)"

# repo_dirty is an alias for repo_has_dirty.
set +e
repo_dirty "libs/clean-repo"
_rd2_rc=$?
set -e
assert_eq "$_rd2_rc" "1" "repo_dirty alias returns 1"

# remote_exists: verifies origin remote is configured.
# The mock returns a remote URL, so it succeeds.
assert_ok "remote exists with mock" -- remote_exists "libs/clean-repo"

printf 'All tests passed.\n'
