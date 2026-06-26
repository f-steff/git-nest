#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin foreach_commands

work=$(test_workspace foreach_stress)

remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

# Create three modules so foreach can distinguish all modules from pending only.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

# Initialize the workspace with three manifest modules.
cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote_one" libs/one >/dev/null
"$GIT_STACK" add "$remote_two" libs/two >/dev/null
"$GIT_STACK" add "$remote_three" libs/three >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null

"$GIT_STACK" start XX-456-foreach-stress >/dev/null

# Modify two modules differently so upload records only those as pending.
printf 'modified in one\n' >>libs/one/file.txt
printf 'added in one\n' >libs/one/added.txt
git -C libs/one add file.txt added.txt
git -C libs/one commit -m "XX-456 modify and add in one" >/dev/null

git -C libs/two rm file.txt >/dev/null
git -C libs/two commit -m "XX-456 delete in two" >/dev/null

"$GIT_STACK" upload >/dev/null

# Leave the third module dirty but not pending; foreach sees it, foreach-modified should not.
printf 'dirty but finalized\n' >>libs/three/file.txt

# Capture foreach environment from every checked-out module.
"$GIT_STACK" foreach -- sh -c '
    printf "%s|%s|%s|%s\n" \
        "$GIT_STACK_MODULE_PATH" \
        "$GIT_STACK_BRANCH" \
        "$(git status --short | wc -l | tr -d " ")" \
        "$PWD" >>"$GIT_STACK_ROOT/foreach_all.txt"
'

# Capture foreach-modified environment from pending modules only.
"$GIT_STACK" foreach-modified -- sh -c '
    printf "%s|%s|%s|%s\n" \
        "$GIT_STACK_MODULE_PATH" \
        "$GIT_STACK_PENDING_BRANCH" \
        "$GIT_STACK_BASE_REVISION" \
        "$GIT_STACK_PUSHED_COMMIT" >>"$GIT_STACK_ROOT/foreach_pending.txt"
'

# Verify foreach covered all modules and reflected dirty state in module three.
test "$(wc -l <foreach_all.txt | tr -d ' ')" = "3"
assert_file_contains foreach_all.txt "libs/one|XX-456-foreach-stress|0|"
assert_file_contains foreach_all.txt "libs/two|XX-456-foreach-stress|0|"
assert_file_contains foreach_all.txt "libs/three|XX-456-foreach-stress|1|"

test "$(wc -l <foreach_pending.txt | tr -d ' ')" = "2"
assert_file_contains foreach_pending.txt "libs/one|XX-456-foreach-stress|"
assert_file_contains foreach_pending.txt "libs/two|XX-456-foreach-stress|"
assert_file_not_contains foreach_pending.txt "libs/three|"

# Confirm the manifest still has all modules even when only two are pending.
assert_file_contains .stack '[module "libs/one"]'
assert_file_contains .stack '[module "libs/two"]'
assert_file_contains .stack '[module "libs/three"]'

# A failing per-module command should stop iteration and return nonzero.
if "$GIT_STACK" foreach-modified -- sh -c 'test "$GIT_STACK_MODULE_PATH" != "libs/two"' >/dev/null 2>&1; then
    echo "foreach-modified should return the first failing command exit code" >&2
    exit 1
fi
