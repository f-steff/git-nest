#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_status_porcelain

test_step "Exercise command status porcelain" "This test verifies the documented command status porcelain behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_status_porcelain)
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

"$GIT_LEGO" status --porcelain >"$root/clean.out"
test ! -s "$root/clean.out"
assert_exit_code 0 "$GIT_LEGO" status --exit-code >/dev/null 2>&1

printf 'outer\n' >rootnote.txt
"$GIT_LEGO" status --porcelain >"$root/dirty_outer.out"
assert_file_contains "$root/dirty_outer.out" "D${tab}.${tab}dirty${tab}-${tab}-${tab}-${tab}?? rootnote.txt"
assert_exit_code 1 "$GIT_LEGO" status --exit-code >/dev/null 2>&1
rm -f rootnote.txt

printf 'subproject dirty\n' >>libs/foo/file.txt
"$GIT_LEGO" status --porcelain >"$root/dirty_module.out"
assert_file_contains "$root/dirty_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab} M file.txt"
git -C libs/foo checkout -- file.txt

printf 'scratch\n' >libs/foo/scratch.txt
"$GIT_LEGO" status --porcelain >"$root/untracked_module.out"
assert_file_contains "$root/untracked_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab}?? scratch.txt"
rm -f libs/foo/scratch.txt

printf 'staged\n' >libs/foo/staged.txt
git -C libs/foo add staged.txt
"$GIT_LEGO" status --porcelain >"$root/staged_module.out"
assert_file_contains "$root/staged_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab}A  staged.txt"
git -C libs/foo reset --hard >/dev/null

rm -f libs/foo/file.txt
"$GIT_LEGO" status --porcelain >"$root/deleted_module.out"
assert_file_contains "$root/deleted_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab} D file.txt"
git -C libs/foo reset --hard >/dev/null

rm -rf libs/foo

"$GIT_LEGO" status --porcelain >"$root/missing.out"
assert_file_contains "$root/missing.out" "M${tab}libs/foo${tab}missing${tab}-${tab}-${tab}-${tab}checkout-missing"

"$GIT_LEGO" status --porcelain --recursive >"$root/order_one.out"
"$GIT_LEGO" status --recursive --porcelain >"$root/order_two.out"
cmp -s "$root/order_one.out" "$root/order_two.out"

describe_result "The command status porcelain behavior matched the expected command output and repository state."
