#!/bin/sh
# Test: outdated checks remotes for newer target-branch commits without changing checkouts

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_outdated_remote_check

test_step "Exercise command outdated remote check" "This test verifies the documented command outdated remote check behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_outdated_remote_check)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"
tab=$(printf '\t')

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

initial=$(git -C "$seed" rev-parse HEAD)
initial_short=$(printf '%s\n' "$initial" | cut -c1-12)
"$GIT_NEST" outdated >outdated_initial.out
assert_file_contains outdated_initial.out "libs/foo: up to date main $initial_short"
"$GIT_NEST" outdated --porcelain >outdated_initial_porcelain.out
test ! -s outdated_initial_porcelain.out

printf 'second\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "second" >/dev/null
git -C "$seed" push origin main >/dev/null
second=$(git -C "$seed" rev-parse HEAD)
second_short=$(printf '%s\n' "$second" | cut -c1-12)

head_before=$(git -C libs/foo rev-parse HEAD)
cp .gitnest project.before
"$GIT_NEST" outdated >outdated_second.out || test "$?" = "1"
assert_file_contains outdated_second.out "libs/foo: outdated main $initial_short -> $second_short"
"$GIT_NEST" outdated --porcelain >outdated_second_porcelain.out || test "$?" = "1"
assert_file_contains outdated_second_porcelain.out "O${tab}libs/foo${tab}outdated${tab}main${tab}$initial${tab}$second${tab}remote-target"
"$GIT_NEST" outdated --json >outdated_second.json || test "$?" = "1"
assert_file_contains outdated_second.json '"command":"outdated"'
assert_file_contains outdated_second.json '"path":"libs/foo"'
assert_file_contains outdated_second.json '"state":"outdated"'
python -m json.tool outdated_second.json >/dev/null 2>&1 || python3 -m json.tool outdated_second.json >/dev/null 2>&1 || true
"$GIT_NEST" outdated --porcelain --recursive >outdated_order_one.out || test "$?" = "1"
"$GIT_NEST" outdated --recursive --porcelain >outdated_order_two.out || test "$?" = "1"
cmp -s outdated_order_one.out outdated_order_two.out
test "$(git -C libs/foo rev-parse HEAD)" = "$head_before"
cmp -s .gitnest project.before

missing="$root/missing_checkout"
mkdir -p "$missing"
cp project.before "$missing/.gitnest"
cd "$missing"
"$GIT_NEST" outdated >outdated_missing.out || test "$?" = "1"
assert_file_contains outdated_missing.out "libs/foo: missing checkout; remote main $second_short"
"$GIT_NEST" outdated --porcelain >outdated_missing_porcelain.out || test "$?" = "1"
assert_file_contains outdated_missing_porcelain.out "M${tab}libs/foo${tab}missing${tab}main${tab}-${tab}$second${tab}checkout-missing"

sed 's/^target_branch=.*/target_branch=missing-target/' .gitnest >project.missing-target
mv project.missing-target .gitnest
if "$GIT_NEST" outdated --porcelain >outdated_error_porcelain.out 2>outdated_error_porcelain.err; then
    echo "outdated --porcelain should fail when a target branch is missing" >&2
    exit 1
fi
assert_file_contains outdated_error_porcelain.out "E${tab}libs/foo${tab}remote-branch-missing${tab}missing-target${tab}-${tab}-${tab}remote-branch-missing"
assert_file_contains outdated_error_porcelain.err "remote branch missing-target is missing"

describe_result "The command outdated remote check behavior matched the expected command output and repository state."
