#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_manifest_lock

test_step "Exercise contract manifest lock" "This test verifies the documented contract manifest lock behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_manifest_lock)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
remote_three="$root/remotes/three.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
seed_three="$root/seed/three"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote_one" libs/one >/dev/null
"$GIT_LEGO" add "$remote_two" libs/two >/dev/null
"$GIT_LEGO" add "$remote_three" libs/three >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
"$GIT_LEGO" start LOCK-100 >/dev/null

mkdir .gitlego.lock
{
    printf 'pid=%s\n' "$$"
    printf 'created_utc=2999-01-01T00:00:00Z\n'
} >.gitlego.lock/info
assert_exit_code 4 "$GIT_LEGO" snapshot >active.out 2>active.err
assert_file_contains active.err "could not acquire manifest lock"
rm -rf .gitlego.lock

mkdir .gitlego.lock
{
    printf 'pid=999999\n'
    printf 'created_utc=2000-01-01T00:00:00Z\n'
} >.gitlego.lock/info
if "$GIT_LEGO" snapshot >stale.out 2>stale.err; then
    echo "snapshot should fail on stale lock" >&2
    exit 1
fi
assert_file_contains stale.err "could not acquire manifest lock"
assert_file_contains stale.err "rm -rf .gitlego.lock"
rm -rf .gitlego.lock

for path in libs/one libs/two libs/three; do
    printf 'parallel\n' >>"$path/file.txt"
    git -C "$path" add file.txt
    git -C "$path" commit -m "LOCK-100 work in $path" >/dev/null
done

"$GIT_LEGO" snapshot >snapshot1.out 2>snapshot1.err &
p1=$!
"$GIT_LEGO" snapshot >snapshot2.out 2>snapshot2.err &
p2=$!
wait "$p1"
wait "$p2"

assert_file_contains .gitlego 'pending_branch=LOCK-100'
test "$(grep -c '^pending_branch=LOCK-100$' .gitlego)" = "3"
test ! -d .gitlego.lock

describe_result "The contract manifest lock behavior matched the expected command output and repository state."
