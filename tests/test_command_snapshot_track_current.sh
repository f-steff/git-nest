#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_snapshot_track_current

root=$(test_workspace command_snapshot_track_current)
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
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote_one" libs/one >/dev/null
"$GIT_LEGO" add "$remote_two" libs/two >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Track the current branch layout" "start . should refresh manifest state without switching unrelated subprojects."
git checkout -b TRACK-100-outer >/dev/null
git -C libs/one checkout -b one/TRACK-100 >/dev/null
printf 'snapshot\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "TRACK-100 snapshot one" >/dev/null
run_ok "current branch layout snapshotted and hooks installed" -- "$GIT_LEGO" start . --hooks
assert_file_contains .gitlego "branch=TRACK-100-outer"
assert_file_contains .gitlego "pending_branch=one/TRACK-100"
test "$(git -C libs/two branch --show-current)" = "main"
describe_result "start . recorded the outer branch and pending subproject branch without switching clean subprojects."
