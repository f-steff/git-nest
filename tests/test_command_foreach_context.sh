#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_foreach_context

test_step "Exercise command foreach context" "This test verifies the documented command foreach context behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace command_foreach_context)

remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

# Create three subprojects so foreach can distinguish all subprojects from pending only.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

# Initialize the workspace with three manifest subprojects.
cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
"$GIT_NEST" add "$remote_three" libs/three >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

"$GIT_NEST" start XX-456-foreach-stress >/dev/null

# Modify two subprojects differently so upload records only those as pending.
printf 'modified in one\n' >>libs/one/file.txt
printf 'added in one\n' >libs/one/added.txt
git -C libs/one add file.txt added.txt
git -C libs/one commit -m "XX-456 modify and add in one" >/dev/null

git -C libs/two rm file.txt >/dev/null
git -C libs/two commit -m "XX-456 delete in two" >/dev/null

"$GIT_NEST" upload >/dev/null

# Leave the third subproject dirty but not pending; foreach sees it, foreach-pending should not.
printf 'dirty but finalized\n' >>libs/three/file.txt

# Capture foreach environment from every checked-out subproject.
"$GIT_NEST" foreach -- sh -c '
    printf "%s|%s|%s|%s\n" \
        "$GIT_NEST_SUBPROJECT_PATH" \
        "$GIT_NEST_BRANCH" \
        "$(git status --short | wc -l | tr -d " ")" \
        "$PWD" >>"$GIT_NEST_ROOT/foreach_all.txt"
'

# Capture foreach-pending environment from pending subprojects only.
"$GIT_NEST" foreach-pending -- sh -c '
    printf "%s|%s|%s|%s\n" \
        "$GIT_NEST_SUBPROJECT_PATH" \
        "$GIT_NEST_PENDING_BRANCH" \
        "$GIT_NEST_BASE_REVISION" \
        "$GIT_NEST_PUSHED_COMMIT" >>"$GIT_NEST_ROOT/foreach_pending.txt"
'

"$GIT_NEST" foreach -- sh -c '
    printf "%s|%s\n" "$GIT_NEST_SUBPROJECT_PATH" "$1" >>"$GIT_NEST_ROOT/foreach_args.txt"
' sh "argument with spaces"

# Verify foreach covered all subprojects and reflected dirty state in subproject three.
test "$(wc -l <foreach_all.txt | tr -d ' ')" = "3"
assert_file_contains foreach_all.txt "libs/one|XX-456-foreach-stress|0|"
assert_file_contains foreach_all.txt "libs/two|XX-456-foreach-stress|0|"
assert_file_contains foreach_all.txt "libs/three|XX-456-foreach-stress|1|"
test "$(wc -l <foreach_args.txt | tr -d ' ')" = "3"
assert_file_contains foreach_args.txt "libs/one|argument with spaces"
assert_file_contains foreach_args.txt "libs/two|argument with spaces"
assert_file_contains foreach_args.txt "libs/three|argument with spaces"

test "$(wc -l <foreach_pending.txt | tr -d ' ')" = "2"
assert_file_contains foreach_pending.txt "libs/one|XX-456-foreach-stress|"
assert_file_contains foreach_pending.txt "libs/two|XX-456-foreach-stress|"
assert_file_not_contains foreach_pending.txt "libs/three|"

# Confirm the manifest still has all subprojects even when only two are pending.
assert_file_contains .gitnest '[subproject "libs/one"]'
assert_file_contains .gitnest '[subproject "libs/two"]'
assert_file_contains .gitnest '[subproject "libs/three"]'

# A failing per-subproject command should stop iteration and return the child exit code.
set +e
"$GIT_NEST" foreach-pending -- sh -c '
    [ "$GIT_NEST_SUBPROJECT_PATH" = "libs/two" ] && exit 7
    exit 0
' >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 7 ]; then
    echo "foreach-pending should return the first failing command exit code" >&2
    exit 1
fi

# Dirty pending subprojects get an explicit composite status row.
printf 'dirty pending\n' >>libs/one/file.txt
"$GIT_NEST" status --porcelain >status_dirty_pending.out
assert_file_contains status_dirty_pending.out "C	libs/one	composite	-	-	-	dirty-and-pending"

describe_result "The command foreach context behavior matched the expected command output and repository state."
