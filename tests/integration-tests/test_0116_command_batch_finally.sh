#!/bin/sh
# Test: restore/snapshot/pull/gc --finally, --finally-no-error, --finally-on-error,
# including the manifest-lock release (re-entrancy) and negative lock test.

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_batch_finally

work=$(test_workspace command_batch_finally)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
# make_bare_remote overwrites the global $work (POSIX sh has no locals);
# re-derive it before building any path from it.
work=$(test_workspace command_batch_finally)
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

test_step "restore --finally-no-error runs after a clean restore" "With all subprojects restorable, the no-error callback must run in the nest root."
rm -f restore-noerr.out
run_ok "restore --finally-no-error ran on success" -- "$GIT_NEST" restore --finally-no-error 'echo restore-noerr > restore-noerr.out'
assert_file_contains restore-noerr.out "restore-noerr"

test_step "restore --finally-on-error runs after a partial failure" "An unreachable remote must make restore report issues and fire the on-error callback."
restore_bad="$work/restore-bad"
mkdir -p "$restore_bad"
rev_one=$(git -C libs/one rev-parse HEAD)
rev_two=$(git -C libs/two rev-parse HEAD)
cat >"$restore_bad/.gitnest" <<EOF
[project]
version=1

[subproject "good/one"]
repo=$remote_one
target_branch=main
revision=$rev_one

[subproject "bad/two"]
repo=file://$work/remotes/does-not-exist.git
target_branch=main
revision=$rev_two
EOF
cd "$restore_bad"
rm -f onerr.out
run_fail "restore with an unreachable remote exited nonzero" any -- "$GIT_NEST" restore \
    --finally-on-error 'echo restore-onerr > onerr.out'
assert_file_contains onerr.out "restore-onerr"
test -d good/one/.git
cd "$outer"

test_step "snapshot --finally-no-error runs after a clean snapshot" "A successful snapshot must fire the no-error callback."
rm -f snap-noerr.out
run_ok "snapshot --finally-no-error ran on success" -- "$GIT_NEST" snapshot --finally-no-error 'echo snap-noerr > snap-noerr.out'
assert_file_contains snap-noerr.out "snap-noerr"

test_step "snapshot --finally-on-error runs when a subproject is dirty" "A dirty subproject makes snapshot report issues (non-strict) and fire the on-error callback."
printf 'dirty\n' >>libs/two/file.txt
rm -f snap-onerr.out snap-noerr.out
run_fail "snapshot --check --strict with a dirty subproject exited nonzero" any -- "$GIT_NEST" snapshot --check --strict \
    --finally-no-error 'echo snap-noerr > snap-noerr.out' \
    --finally-on-error 'echo snap-onerr > snap-onerr.out'
assert_file_contains snap-onerr.out "snap-onerr"
if [ -e snap-noerr.out ]; then
    printf 'UNEXPECTED RESULT: snap-noerr.out must not exist after a failing snapshot\n' >&2
    exit 1
fi
git -C libs/two checkout -- file.txt

test_step "gc --finally-no-error runs after a successful gc" "A clean gc run must fire the no-error callback."
rm -f gc-noerr.out
run_ok "gc --finally-no-error ran on success" -- "$GIT_NEST" gc --finally-no-error 'echo gc-noerr > gc-noerr.out'
assert_file_contains gc-noerr.out "gc-noerr"

test_step "pull --finally-no-error 'git-nest snapshot' re-entrancy (lock released)" "The manifest lock must be released before callbacks run, so a callback can invoke git-nest without a lock timeout."
run_ok "pull --finally-no-error 'git-nest snapshot' completed without lock timeout" -- "$GIT_NEST" pull --finally-no-error "$GIT_NEST snapshot >/dev/null 2>&1"

test_step "Negative lock test: the callback lock must be released, not held" "If the lock were still held by the parent pull, the callback's git-nest snapshot would exit 4 after the timeout; it must complete with exit 0 instead."
run_ok "pull --finally 'git-nest status' did not deadlock on the manifest lock" -- "$GIT_NEST" pull --finally-no-error "$GIT_NEST status >/dev/null 2>neg_lock.err"
if grep -q "could not acquire manifest lock" neg_lock.err; then
    printf 'UNEXPECTED RESULT: callback hit a held manifest lock (deadlock)\n' >&2
    exit 1
fi

test_step "Direct negative test: a held lock outside callbacks still fails" "The lock release must be scoped to callbacks only; a deliberately held lock must still be reported."
mkdir .gitnest.lock
printf 'pid=999999\ncreated_utc=2026-07-08T00:00:00Z\n' >.gitnest.lock/info
run_fail "snapshot with a foreign held lock still fails with exit 4" 4 -- sh -c 'GIT_NEST_LOCK_TIMEOUT_SECONDS=1 "$1" snapshot >/dev/null 2>held.err' sh "$GIT_NEST"
assert_file_contains held.err "could not acquire manifest lock"
rm -rf .gitnest.lock

test_step "Batch commands reject --finally* with machine-readable output" "gc --json cannot be combined with a callback."
run_fail "gc --json with --finally rejected" 2 -- sh -c '"$1" gc --json --finally "echo x" >/dev/null 2>gc_mutex.err' sh "$GIT_NEST"
assert_file_contains gc_mutex.err "cannot be combined"
run_fail "pull --json with --finally-on-error rejected" 2 -- sh -c '"$1" pull --json --finally-on-error "echo x" >/dev/null 2>pull_mutex.err' sh "$GIT_NEST"
assert_file_contains pull_mutex.err "cannot be combined"

describe_result "restore/snapshot/pull/gc --finally flags fire per exit status, the manifest lock is released for re-entrant callbacks (negative test proves a held lock still fails), and machine-readable combinations are rejected."
