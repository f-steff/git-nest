#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin status_porcelain

root=$(test_workspace status_porcelain)
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

"$GIT_STACK" status --porcelain >"$root/clean.out"
test ! -s "$root/clean.out"

printf 'outer\n' >rootnote.txt
"$GIT_STACK" status --porcelain >"$root/dirty_outer.out"
assert_file_contains "$root/dirty_outer.out" ".${tab}?? rootnote.txt"
rm -f rootnote.txt

printf 'module dirty\n' >>libs/foo/file.txt
"$GIT_STACK" status --porcelain >"$root/dirty_module.out"
assert_file_contains "$root/dirty_module.out" "libs/foo${tab} M file.txt"

printf 'scratch\n' >libs/foo/scratch.txt
"$GIT_STACK" status --porcelain >"$root/untracked_module.out"
assert_file_contains "$root/untracked_module.out" "libs/foo${tab}?? scratch.txt"

git -C libs/foo checkout -- file.txt
rm -f libs/foo/scratch.txt
rm -rf libs/foo

"$GIT_STACK" status --porcelain >"$root/missing.out"
assert_file_contains "$root/missing.out" "libs/foo${tab}!! missing"

"$GIT_STACK" status --porcelain --recursive >"$root/order_one.out"
"$GIT_STACK" status --recursive --porcelain >"$root/order_two.out"
cmp -s "$root/order_one.out" "$root/order_two.out"
