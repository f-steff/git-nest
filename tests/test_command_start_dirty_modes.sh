#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_start_dirty_modes

root=$(test_workspace command_start_dirty_modes)
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
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Cancel start when a subproject is dirty" "--cancel-dirty should stop before switching any branch."
printf 'dirty\n' >>libs/one/file.txt
before_outer=$(git branch --show-current)
before_one=$(git -C libs/one branch --show-current)
run_fail "dirty workspace canceled before branch switching" any -- sh -c '"$1" start --cancel-dirty XX-888-dirty >cancel.out 2>cancel.err' sh "$GIT_NEST"
test "$(git branch --show-current)" = "$before_outer"
test "$(git -C libs/one branch --show-current)" = "$before_one"
assert_file_contains cancel.err "start canceled"

test_step "Stash dirty work during start" "--stash-dirty should preserve dirty work and switch all repositories."
run_ok "dirty work stashed and project branch started" -- "$GIT_NEST" start --stash-dirty XX-888-dirty
test "$(git branch --show-current)" = "XX-888-dirty"
test "$(git -C libs/one branch --show-current)" = "XX-888-dirty"
test -z "$(git -C libs/one status --porcelain)"
git -C libs/one stash list | grep "git-nest start preflight" >/dev/null

test_step "Discard tracked edits but refuse untracked files" "--discard-dirty must not silently delete untracked work."
git -C libs/two checkout main >/dev/null
printf 'tracked\n' >>libs/two/file.txt
printf 'untracked\n' >libs/two/untracked.txt
run_fail "untracked file blocked discard mode" any -- sh -c '"$1" start --discard-dirty XX-999-discard >discard.out 2>discard.err' sh "$GIT_NEST"
assert_file_contains discard.err "still has untracked files"
test -f libs/two/untracked.txt
rm -f libs/two/untracked.txt
test -z "$(git -C libs/two status --porcelain)"
describe_result "start handled cancel, stash, and discard safety modes without losing untracked work."
