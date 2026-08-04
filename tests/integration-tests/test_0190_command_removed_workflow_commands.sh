#!/bin/sh
# Test: retired and renamed commands are rejected with migration guidance

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_removed_workflow_commands

test_step "Reject removed workflow commands" "Old branch/upload/finalize/pending command names should fail with guidance instead of silently doing work."

root=$(test_workspace command_removed_workflow_commands)
outer="$root/outer"
make_repo "$outer"
cd "$outer"
"$GIT_NEST" init >/dev/null

assert_removed() {
    command_name=$1
    expected=$2
    shift 2
    if "$GIT_NEST" "$command_name" "$@" >"$command_name.out" 2>"$command_name.err"; then
        echo "$command_name should be rejected" >&2
        exit 1
    fi
    assert_file_contains "$command_name.err" "$expected"
}

assert_removed start "use Git branch commands and git-nest snapshot" .
assert_removed upload "use git push and git-nest snapshot"
assert_removed finalize "use git-nest snapshot to record reproducible revisions" .
assert_removed sync "use restore"
assert_removed install-hooks "use hooks-install"
assert_removed remove-hooks "use hooks-uninstall"
assert_removed no-pending "pending manifest state is no longer supported"
assert_removed foreach-pending "pending manifest state is no longer supported" -- true
assert_removed cleanup-branches "git-nest no longer deletes Git branches"
# extract was renamed: absorb now covers files, repositories, and submodules.
assert_removed extract "use git-nest absorb" src/lib "file:///tmp/none.git"
# repair was renamed to tidy.
assert_removed repair "use git-nest tidy"

describe_result "Removed workflow commands failed with migration guidance."
