#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_foreach_filters

work=$(test_workspace command_foreach_filters)
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
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Dirty one subproject" "foreach-modified and foreach-clean should partition checked-out subprojects by working-tree state."
printf 'dirty work\n' >>libs/two/file.txt

run_capture "dirty subproject listed in porcelain output" foreach_modified.out foreach_modified.err -- "$GIT_NEST" foreach-modified --porcelain
assert_file_contains foreach_modified.out "F	libs/two	modified"
assert_file_not_contains foreach_modified.out "libs/one"
assert_file_not_contains foreach_modified.out "libs/three"
run_capture "clean subprojects listed in porcelain output" foreach_clean.out foreach_clean.err -- "$GIT_NEST" foreach-clean --porcelain
assert_file_contains foreach_clean.out "F	libs/one	clean"
assert_file_contains foreach_clean.out "F	libs/three	clean"
assert_file_not_contains foreach_clean.out "libs/two"
run_capture "dirty subproject listed in JSON output" foreach_modified.json foreach_modified_json.err -- "$GIT_NEST" foreach-modified --json
assert_file_contains foreach_modified.json '"command":"foreach-modified"'
assert_file_contains foreach_modified.json '"path":"libs/two"'

test_step "Run commands through filtered foreach modes" "the selected subproject context should be exposed through environment variables."
run_ok "foreach-modified ran only in the dirty subproject" -- "$GIT_NEST" foreach-modified -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/modified_command.out"'
assert_file_contains modified_command.out "libs/two"
run_fail "foreach-clean continued through all clean subprojects and returned the failing status" 9 -- sh -c '"$1" foreach-clean --continue-on-error -- sh -c '"'"'
    printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/clean_continue.out"
    [ "$GIT_NEST_SUBPROJECT_PATH" = "libs/one" ] && exit 9
    exit 0
'"'"' >/dev/null 2>&1' sh "$GIT_NEST"
assert_file_contains clean_continue.out "libs/one"
assert_file_contains clean_continue.out "libs/three"
describe_result "foreach-modified and foreach-clean selected the expected repositories and propagated command status."
