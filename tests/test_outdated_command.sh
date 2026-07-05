#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin outdated_command

root=$(test_workspace outdated_command)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"
tab=$(printf '\t')

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

initial=$(git -C "$seed" rev-parse HEAD)
initial_short=$(printf '%s\n' "$initial" | cut -c1-12)
"$GIT_LEGO" outdated >outdated_initial.out
assert_file_contains outdated_initial.out "libs/foo: up to date main $initial_short"
"$GIT_LEGO" outdated --porcelain >outdated_initial_porcelain.out
test ! -s outdated_initial_porcelain.out

printf 'second\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "second" >/dev/null
git -C "$seed" push origin main >/dev/null
second=$(git -C "$seed" rev-parse HEAD)
second_short=$(printf '%s\n' "$second" | cut -c1-12)

head_before=$(git -C libs/foo rev-parse HEAD)
cp .gitlego project.before
"$GIT_LEGO" outdated >outdated_second.out || test "$?" = "1"
assert_file_contains outdated_second.out "libs/foo: outdated main $initial_short -> $second_short"
"$GIT_LEGO" outdated --porcelain >outdated_second_porcelain.out || test "$?" = "1"
assert_file_contains outdated_second_porcelain.out "O${tab}libs/foo${tab}outdated${tab}main${tab}$initial${tab}$second${tab}remote-target"
"$GIT_LEGO" outdated --porcelain --recursive >outdated_order_one.out || test "$?" = "1"
"$GIT_LEGO" outdated --recursive --porcelain >outdated_order_two.out || test "$?" = "1"
cmp -s outdated_order_one.out outdated_order_two.out
test "$(git -C libs/foo rev-parse HEAD)" = "$head_before"
cmp -s .gitlego project.before

git -C libs/foo checkout -b OUTDATED-100-subproject >/dev/null
printf 'pending\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "AVAIL-100 pending" >/dev/null
"$GIT_LEGO" upload >/dev/null
"$GIT_LEGO" outdated >outdated_pending.out
assert_file_contains outdated_pending.out "libs/foo: pending OUTDATED-100-subproject"
"$GIT_LEGO" outdated --porcelain >outdated_pending_porcelain.out
test ! -s outdated_pending_porcelain.out

missing="$root/missing_checkout"
mkdir -p "$missing"
cp project.before "$missing/.gitlego"
cd "$missing"
"$GIT_LEGO" outdated >outdated_missing.out || test "$?" = "1"
assert_file_contains outdated_missing.out "libs/foo: missing checkout; remote main $second_short"
"$GIT_LEGO" outdated --porcelain >outdated_missing_porcelain.out || test "$?" = "1"
assert_file_contains outdated_missing_porcelain.out "M${tab}libs/foo${tab}missing${tab}main${tab}-${tab}$second${tab}checkout-missing"

sed 's/^target_branch=.*/target_branch=missing-target/' .gitlego >project.missing-target
mv project.missing-target .gitlego
if "$GIT_LEGO" outdated --porcelain >outdated_error_porcelain.out 2>outdated_error_porcelain.err; then
    echo "outdated --porcelain should fail when a target branch is missing" >&2
    exit 1
fi
assert_file_contains outdated_error_porcelain.out "E${tab}libs/foo${tab}remote-branch-missing${tab}missing-target${tab}-${tab}-${tab}remote-branch-missing"
assert_file_contains outdated_error_porcelain.err "remote branch missing-target is missing"
