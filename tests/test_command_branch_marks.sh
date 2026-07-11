#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_branch_marks

test_step "Exercise branch mark commands" "Branch marks should remember reusable branch names without creating or deleting Git branches."

root=$(test_workspace command_branch_marks)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

git checkout -b WORK-1 >/dev/null
"$GIT_NEST" branch-mark >/dev/null
(cd libs/foo && git checkout -b WORK-1 >/dev/null && "$GIT_NEST" branch-mark >/dev/null)
(cd libs/foo && git checkout -b WORK-2 >/dev/null && "$GIT_NEST" branch-mark >/dev/null)

assert_file_contains .gitignore ".gitnest-branches"
"$GIT_NEST" branch-list >branches.out
assert_file_contains branches.out "WORK-1	."
assert_file_contains branches.out "WORK-1	libs/foo"
assert_file_contains branches.out "WORK-2	libs/foo"

"$GIT_NEST" branch-list --verbose >branches_verbose.out
assert_file_contains branches_verbose.out "foo.git"
"$GIT_NEST" branch-list --json >branches.json
assert_file_contains branches.json '"branch":"WORK-2"'

(cd libs/foo && "$GIT_NEST" branch-unmark WORK-1 >/dev/null)
"$GIT_NEST" branch-list >branches_after_unmark.out
assert_file_not_contains branches_after_unmark.out "WORK-1	libs/foo"
assert_file_contains branches_after_unmark.out "WORK-1	."

git -C libs/foo checkout main >/dev/null
git -C libs/foo branch -D WORK-2 >/dev/null
"$GIT_NEST" branch-cleanup >cleanup.out
assert_file_contains cleanup.out "Removed 1 stale branch mark(s)."
"$GIT_NEST" branch-list >branches_after_cleanup.out
assert_file_not_contains branches_after_cleanup.out "WORK-2"
git -C . show-ref --verify --quiet refs/heads/WORK-1

describe_result "Branch marks were stored, listed, unmarked, and cleaned without changing Git branch ownership."
