#!/bin/sh
# Test: snapshot path selection for all, root-dot, and subproject-dot

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_snapshot_paths

test_step "Exercise snapshot path selection" "Snapshot should update all subprojects by default, treat root dot as all, and treat subproject dot as that subproject."

root=$(test_workspace command_snapshot_paths)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

printf 'one second\n' >>"$seed_one/file.txt"
git -C "$seed_one" add file.txt
git -C "$seed_one" commit -m "one second" >/dev/null
git -C "$seed_one" push origin main >/dev/null
one_second=$(git -C "$seed_one" rev-parse HEAD)
git -C libs/one fetch origin >/dev/null
git -C libs/one checkout "$one_second" >/dev/null

printf 'two second\n' >>"$seed_two/file.txt"
git -C "$seed_two" add file.txt
git -C "$seed_two" commit -m "two second" >/dev/null
git -C "$seed_two" push origin main >/dev/null
two_second=$(git -C "$seed_two" rev-parse HEAD)
git -C libs/two fetch origin >/dev/null
git -C libs/two checkout "$two_second" >/dev/null

(cd libs/one && "$GIT_NEST" snapshot >/dev/null)
assert_file_contains .gitnest "revision=$one_second"
assert_file_contains .gitnest "revision=$two_second"

printf 'one third\n' >>"$seed_one/file.txt"
git -C "$seed_one" add file.txt
git -C "$seed_one" commit -m "one third" >/dev/null
git -C "$seed_one" push origin main >/dev/null
one_third=$(git -C "$seed_one" rev-parse HEAD)
git -C libs/one fetch origin >/dev/null
git -C libs/one checkout "$one_third" >/dev/null

printf 'two third\n' >>"$seed_two/file.txt"
git -C "$seed_two" add file.txt
git -C "$seed_two" commit -m "two third" >/dev/null
git -C "$seed_two" push origin main >/dev/null
two_third=$(git -C "$seed_two" rev-parse HEAD)
git -C libs/two fetch origin >/dev/null
git -C libs/two checkout "$two_third" >/dev/null

(cd libs/one && "$GIT_NEST" snapshot . >/dev/null)
assert_file_contains .gitnest "revision=$one_third"
assert_file_not_contains .gitnest "revision=$two_third"

"$GIT_NEST" snapshot . >/dev/null
assert_file_contains .gitnest "revision=$two_third"

printf 'dirty\n' >>libs/one/file.txt
"$GIT_NEST" snapshot libs/one >dirty.out 2>dirty.err
assert_file_contains dirty.err "working tree is dirty"
assert_file_contains .gitnest "revision=$one_third"

describe_result "Snapshot path selection matched all, root-dot, and subproject-dot expectations."
