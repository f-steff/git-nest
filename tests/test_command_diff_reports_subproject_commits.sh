#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_diff_reports_subproject_commits

work=$(test_workspace command_diff_reports_subproject_commits)
remote="$work/remotes/one.git"
seed="$work/seed/one"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/one >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Create a subproject commit ahead of the manifest revision" "diff should report subproject commits not represented by .gitnest."
printf 'local feature\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "local feature for diff" >/dev/null

run_fail "human diff reports the local subproject commit" 1 -- sh -c '"$1" diff >diff.out 2>diff.err' sh "$GIT_NEST"
assert_file_contains diff.out "libs/one:"
assert_file_contains diff.out "local feature for diff"
run_fail "diff --stat reports changed file details" 1 -- sh -c '"$1" diff --stat >diff_stat.out 2>diff_stat.err' sh "$GIT_NEST"
assert_file_contains diff_stat.out "local feature for diff"
assert_file_contains diff_stat.out "file.txt"
run_fail "diff --json reports machine-readable commit rows" 1 -- sh -c '"$1" diff --json >diff.json 2>diff_json.err' sh "$GIT_NEST"
assert_file_contains diff.json '"command":"diff"'
assert_file_contains diff.json "local feature for diff"

test_step "Freeze the current revision and compare against previous manifest state" "diff should become clean for the current manifest and still report differences with --since."
"$GIT_NEST" freeze --force --only libs/one >/dev/null
git add .gitnest
git commit -m "freeze one" >/dev/null
run_capture "current manifest has no subproject differences" diff_clean.out diff_clean.err -- "$GIT_NEST" diff
assert_file_contains diff_clean.out "No subproject commit differences"
run_fail "diff --since reports the earlier manifest difference" 1 -- sh -c '"$1" diff --since HEAD~1 >diff_since.out 2>diff_since.err' sh "$GIT_NEST"
assert_file_contains diff_since.out "local feature for diff"
run_fail "diff --since rejects missing refs" any -- sh -c '"$1" diff --since does-not-exist >diff_missing.out 2>diff_missing.err' sh "$GIT_NEST"
assert_file_contains diff_missing.err "cannot read .gitnest at does-not-exist"
describe_result "diff reported human, stat, JSON, clean, --since, and bad-ref paths."
