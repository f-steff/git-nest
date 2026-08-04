#!/bin/sh
# Test: the manifest lock is released after success and after a mid-command error

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_lock_release

test_step "Exercise manifest lock release" "A command that acquires the manifest lock must release it via the exit handler both on success and when it errors after taking the lock, so the workspace is never left locked."

root=$(test_workspace contract_lock_release)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null

test_step "Lock released after a successful command" "add takes the lock; once it finishes the .gitnest.lock directory must be gone."
"$GIT_NEST" add "$remote" libs/foo >/dev/null
test ! -e .gitnest.lock

test_step "Lock released after an error that occurs while holding the lock" "A case-collision add fails after acquiring the lock; the exit handler must still remove .gitnest.lock."
if "$GIT_NEST" add "$remote" libs/FOO >collide.out 2>collide.err; then
    printf 'UNEXPECTED RESULT: case-collision add should have failed\n' >&2
    exit 1
fi
assert_file_contains collide.err "collides with existing subproject"
test ! -e .gitnest.lock

test_step "A subsequent command can take the lock again" "Because the lock was released, another lock-taking command succeeds without a timeout." 
"$GIT_NEST" add "$remote" libs/bar >/dev/null
test ! -e .gitnest.lock

describe_result "The manifest lock was released after both a successful command and a mid-command error, and could be re-acquired."
