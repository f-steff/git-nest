#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin available_command

root=$(test_workspace available_command)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"
tab=$(printf '\t')

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote" libs/foo >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null

initial=$(git -C "$seed" rev-parse HEAD)
initial_short=$(printf '%s\n' "$initial" | cut -c1-12)
"$GIT_STACK" available >available_initial.out
assert_file_contains available_initial.out "libs/foo: up to date main $initial_short"
"$GIT_STACK" available --porcelain >available_initial_porcelain.out
test ! -s available_initial_porcelain.out

printf 'second\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "second" >/dev/null
git -C "$seed" push origin main >/dev/null
second=$(git -C "$seed" rev-parse HEAD)
second_short=$(printf '%s\n' "$second" | cut -c1-12)

head_before=$(git -C libs/foo rev-parse HEAD)
cp .stack stack.before
"$GIT_STACK" available >available_second.out
assert_file_contains available_second.out "libs/foo: available main $initial_short -> $second_short"
"$GIT_STACK" available --porcelain >available_second_porcelain.out
assert_file_contains available_second_porcelain.out "libs/foo${tab}available${tab}main${tab}$initial${tab}$second"
"$GIT_STACK" available --porcelain --recursive >available_order_one.out
"$GIT_STACK" available --recursive --porcelain >available_order_two.out
cmp -s available_order_one.out available_order_two.out
test "$(git -C libs/foo rev-parse HEAD)" = "$head_before"
cmp -s .stack stack.before

git -C libs/foo checkout -b AVAIL-100-module >/dev/null
printf 'pending\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "AVAIL-100 pending" >/dev/null
"$GIT_STACK" upload >/dev/null
"$GIT_STACK" available >available_pending.out
assert_file_contains available_pending.out "libs/foo: pending AVAIL-100-module"
"$GIT_STACK" available --porcelain >available_pending_porcelain.out
test ! -s available_pending_porcelain.out

missing="$root/missing_checkout"
mkdir -p "$missing"
cp stack.before "$missing/.stack"
cd "$missing"
"$GIT_STACK" available >available_missing.out
assert_file_contains available_missing.out "libs/foo: missing checkout; remote main $second_short"
"$GIT_STACK" available --porcelain >available_missing_porcelain.out
assert_file_contains available_missing_porcelain.out "libs/foo${tab}missing${tab}main${tab}$second"

sed 's/^target_branch=.*/target_branch=missing-target/' .stack >stack.missing-target
mv stack.missing-target .stack
if "$GIT_STACK" available --porcelain >available_error_porcelain.out 2>available_error_porcelain.err; then
    echo "available --porcelain should fail when a target branch is missing" >&2
    exit 1
fi
assert_file_contains available_error_porcelain.out "libs/foo${tab}error${tab}remote-branch-missing${tab}missing-target"
assert_file_contains available_error_porcelain.err "remote branch missing-target is not available"
