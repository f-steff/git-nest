#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_upload_branch_names

test_step "Exercise command upload branch names" "This test verifies the documented command upload branch names behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace command_upload_branch_names)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

# Create three subprojects so upload can compare changed and unchanged candidates.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

# Initialize the workspace and create the outer project branch in all subprojects.
cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
"$GIT_NEST" add "$remote_three" libs/three >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
"$GIT_NEST" start XX-777-project >/dev/null

# Move two subprojects onto subproject-specific branch names and commit work there.
git -C libs/one checkout -b subproject-one/XX-777 >/dev/null
printf 'one\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "XX-777 one work" >/dev/null

git -C libs/two checkout -b subproject-two-XX-777 >/dev/null
printf 'two\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "XX-777 two work" >/dev/null

# Upload should push only changed subprojects and record their actual branch names.
"$GIT_NEST" upload >/dev/null

assert_file_contains .gitnest '[subproject "libs/one"]'
assert_file_contains .gitnest 'pending_branch=subproject-one/XX-777'
assert_file_contains .gitnest '[subproject "libs/two"]'
assert_file_contains .gitnest 'pending_branch=subproject-two-XX-777'
assert_file_not_contains .gitnest 'pending_branch=XX-777-project'

# The unchanged candidate branch in subproject three must not be pushed or pending.
git --git-dir="$remote_one" show-ref --verify --quiet refs/heads/subproject-one/XX-777
git --git-dir="$remote_two" show-ref --verify --quiet refs/heads/subproject-two-XX-777
if git --git-dir="$remote_three" show-ref --verify --quiet refs/heads/XX-777-project; then
    echo "unchanged candidate subproject should not be pushed" >&2
    exit 1
fi
if grep -A5 '^\[subproject "libs/three"\]$' .gitnest | grep -F 'pending_branch=' >/dev/null; then
    echo "unchanged candidate subproject should not become pending" >&2
    exit 1
fi

# Any dirty checked-out subproject blocks upload before manifest state changes.
printf 'dirty\n' >>libs/three/file.txt
if "$GIT_NEST" upload >dirty_upload.out 2>dirty_upload.err; then
    echo "upload should fail when a subproject has uncommitted changes" >&2
    exit 1
fi
assert_file_contains dirty_upload.err "subproject libs/three has uncommitted changes"

if "$GIT_NEST" upload --unknown >unknown_upload.out 2>unknown_upload.err; then
    echo "upload should reject unknown options" >&2
    exit 1
fi
assert_file_contains unknown_upload.err "unknown upload option: --unknown"

describe_result "The command upload branch names behavior matched the expected command output and repository state."
