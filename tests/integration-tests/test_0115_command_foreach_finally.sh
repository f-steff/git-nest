#!/bin/sh
# Test: foreach/foreach-modified/foreach-clean --finally, --finally-no-error, --finally-on-error

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_foreach_finally

work=$(test_workspace command_foreach_finally)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
"$GIT_NEST" add "$remote_three" libs/three >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

test_step "--finally always fires once after the loop" "A plain --finally callback must run exactly once, in the nest root, after all subproject iterations regardless of their exit status."
run_ok "foreach --finally ran the callback once after success" -- "$GIT_NEST" foreach --finally 'echo finally-ran > finally.out' -- sh -c 'true'
assert_file_contains finally.out "finally-ran"
run_ok "foreach --finally with multiple subprojects ran the callback exactly once" -- "$GIT_NEST" foreach --finally 'echo once >> finally-count.out' -- sh -c 'true'
[ "$(wc -l < finally-count.out)" -eq 1 ] || {
    printf 'UNEXPECTED RESULT: --finally must run once, got %s lines\n' "$(wc -l < finally-count.out)" >&2
    exit 1
}

test_step "--finally-no-error fires only when every subproject command succeeded" "With all subproject commands exiting 0, the no-error callback must run."
run_ok "foreach --finally-no-error ran on full success" -- "$GIT_NEST" foreach --finally-no-error 'echo noerr-ran > noerr.out' -- sh -c 'true'
assert_file_contains noerr.out "noerr-ran"

test_step "--finally-on-error fires when a subproject command fails" "A failing subproject command must trigger the on-error callback and skip the no-error callback."
rm -f onerr.out noerr.out
run_fail "foreach with failing subproject command exited nonzero" any -- "$GIT_NEST" foreach \
    --finally-no-error 'echo noerr-ran > noerr.out' \
    --finally-on-error 'echo onerr-ran > onerr.out' \
    -- sh -c 'test "$GIT_NEST_SUBPROJECT_PATH" != libs/one'
assert_file_contains onerr.out "onerr-ran"
if [ -e noerr.out ]; then
    printf 'UNEXPECTED RESULT: noerr.out should not exist after a failure\n' >&2
    exit 1
fi

test_step "--continue-on-error with --finally-on-error fires once at the end" "With --continue-on-error the loop keeps going past the first failure and the on-error callback fires exactly once afterwards."
printf 'dirty work\n' >>libs/two/file.txt
rm -f onerr.out
run_fail "foreach-modified --continue-on-error with a failing subproject exited nonzero" any -- "$GIT_NEST" foreach-modified \
    --continue-on-error \
    --finally-on-error 'echo onerr-ran > onerr.out' \
    -- sh -c 'false'
assert_file_contains onerr.out "onerr-ran"

test_step "Callbacks receive the nest root via GIT_NEST_ROOT and run in the root" "The callback must run in the nest root directory with GIT_NEST_ROOT exported."
# git rev-parse --show-toplevel (repo_root) and pwd can disagree on path
# spelling across platforms (MSYS /tmp vs C:/... on Windows CI), so verify
# the recorded root semantically: it must be the directory that owns
# .gitnest, and the callback's cwd must be that same directory.
run_ok "callback observed GIT_NEST_ROOT and the root cwd" -- "$GIT_NEST" foreach --finally 'echo "$GIT_NEST_ROOT" > root-observed.out; pwd > callback-cwd.out' -- sh -c 'true'
[ -s root-observed.out ] || {
    printf 'UNEXPECTED RESULT: GIT_NEST_ROOT was not written by the callback\n' >&2
    exit 1
}
root_recorded=$(cat root-observed.out)
[ -f "$root_recorded/.gitnest" ] || {
    printf 'UNEXPECTED RESULT: GIT_NEST_ROOT %s does not own .gitnest\n' "$root_recorded" >&2
    exit 1
}
[ -s callback-cwd.out ] || {
    printf 'UNEXPECTED RESULT: callback cwd was not written\n' >&2
    exit 1
}
cwd_recorded=$(cat callback-cwd.out)
[ -f "$cwd_recorded/.gitnest" ] || {
    printf 'UNEXPECTED RESULT: callback cwd %s does not own .gitnest\n' "$cwd_recorded" >&2
    exit 1
}

test_step "Callback may invoke git-nest itself (nested-nest / re-entrancy usage)" "The manifest lock is released before callbacks run, so a callback can call git-nest snapshot without deadlocking."
run_ok "foreach --finally-no-error 'git-nest snapshot' completed without lock timeout" -- "$GIT_NEST" foreach \
    --finally-no-error 'git -C "$GIT_NEST_ROOT" "$GIT_NEST" snapshot >/dev/null 2>&1' \
    -- sh -c 'true'

test_step "Mutual exclusion with machine-readable output" "--finally* requires a command, so it cannot be combined with --porcelain or --json."
run_fail "foreach-modified --finally with --porcelain rejected" 2 -- sh -c '"$1" foreach-modified --finally "echo x" --porcelain >/dev/null 2>mutex_porcelain.err' sh "$GIT_NEST"
assert_file_contains mutex_porcelain.err "cannot be combined"
run_fail "foreach-modified --finally with --json rejected" 2 -- sh -c '"$1" foreach-modified --json --finally "echo x" >/dev/null 2>mutex_json.err' sh "$GIT_NEST"
assert_file_contains mutex_json.err "cannot be combined"

test_step "Missing callback argument is a usage error" "Each --finally* flag requires exactly one shell-command argument."
run_fail "foreach --finally without an argument rejected" 2 -- "$GIT_NEST" foreach --finally

test_step "foreach-clean also supports the finally flags" "foreach-clean shares the filtered engine, so the same callback semantics apply."
run_ok "foreach-clean --finally-no-error ran on clean subprojects" -- "$GIT_NEST" foreach-clean --finally-no-error 'echo clean-noerr > clean-noerr.out' -- sh -c 'true'
assert_file_contains clean-noerr.out "clean-noerr"

describe_result "foreach/foreach-modified/foreach-clean --finally, --finally-no-error, and --finally-on-error fire per exit status, support re-entrant git-nest callbacks, and reject machine-readable combinations."
