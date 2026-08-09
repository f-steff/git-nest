#!/bin/sh
# Test: single-pass foreach-modified branch/commit/push recipe spans dirty subprojects, then snapshot pins the new revisions

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_foreach_feature_branch

work=$(test_workspace workflow_foreach_feature_branch)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
"$GIT_NEST" add "$remote_three" libs/three >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

three_before=$(git -C libs/three rev-parse HEAD)

test_step "Make two subprojects dirty and leave one clean" "foreach-modified should select only the dirty subprojects for the feature."
printf 'shared change one\n' >>libs/one/file.txt
printf 'shared change two\n' >>libs/two/file.txt

run_capture "dirty subprojects previewed" preview.out preview.err -- "$GIT_NEST" foreach-modified --porcelain
assert_file_contains preview.out "libs/one"
assert_file_contains preview.out "libs/two"
assert_file_not_contains preview.out "libs/three"

test_step "Run the single-pass branch, commit, and push recipe" "one foreach-modified pass should move each dirty subproject onto the feature branch, commit, and push it before the commit makes it clean."
run_ok "single-pass feature recipe succeeded across dirty subprojects" -- \
    "$GIT_NEST" foreach-modified --continue-on-error -- \
    sh -c 'git switch -c feature/shared-cache && git add -A && git commit -m "shared change" && git push -u origin HEAD'

test_step "Verify each participating repository joined the feature branch" "the dirty subprojects should be on feature/shared-cache locally and on their remotes; the clean subproject should be untouched."
git -C libs/one symbolic-ref --short HEAD >branch_one.txt
git -C libs/two symbolic-ref --short HEAD >branch_two.txt
git -C libs/three symbolic-ref --short HEAD >branch_three.txt
assert_file_contains branch_one.txt "feature/shared-cache"
assert_file_contains branch_two.txt "feature/shared-cache"
assert_file_contains branch_three.txt "main"

git ls-remote "$remote_one" "refs/heads/feature/shared-cache" >lsremote_one.txt
git ls-remote "$remote_two" "refs/heads/feature/shared-cache" >lsremote_two.txt
git ls-remote "$remote_three" "refs/heads/feature/shared-cache" >lsremote_three.txt
assert_file_contains lsremote_one.txt "refs/heads/feature/shared-cache"
assert_file_contains lsremote_two.txt "refs/heads/feature/shared-cache"
assert_file_not_contains lsremote_three.txt "refs/heads/feature/shared-cache"

test_step "Record reproducible revisions with snapshot" "snapshot should pin the pushed feature commits for the participating subprojects and leave the untouched subproject alone."
one_after=$(git -C libs/one rev-parse HEAD)
two_after=$(git -C libs/two rev-parse HEAD)
run_ok "snapshot recorded the new subproject revisions" -- "$GIT_NEST" snapshot
assert_file_contains .gitnest "$one_after"
assert_file_contains .gitnest "$two_after"
assert_file_contains .gitnest "$three_before"

describe_result "The single-pass foreach-modified recipe branched, committed, and pushed the dirty subprojects together, left the clean subproject alone, and snapshot pinned the new revisions in .gitnest."
