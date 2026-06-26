#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin upload_branch_behaviour

work=$(test_workspace upload_branch_behaviour)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

# Create three modules so upload can compare changed and unchanged candidates.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

# Initialize the workspace and create the outer stack branch in all modules.
cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote_one" libs/one >/dev/null
"$GIT_STACK" add "$remote_two" libs/two >/dev/null
"$GIT_STACK" add "$remote_three" libs/three >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null
"$GIT_STACK" start XX-777-stack >/dev/null

# Move two modules onto module-specific branch names and commit work there.
git -C libs/one checkout -b module-one/XX-777 >/dev/null
printf 'one\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "XX-777 one work" >/dev/null

git -C libs/two checkout -b module-two-XX-777 >/dev/null
printf 'two\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "XX-777 two work" >/dev/null

# Upload should push only changed modules and record their actual branch names.
"$GIT_STACK" upload >/dev/null

assert_file_contains .stack '[module "libs/one"]'
assert_file_contains .stack 'pending_branch=module-one/XX-777'
assert_file_contains .stack '[module "libs/two"]'
assert_file_contains .stack 'pending_branch=module-two-XX-777'
assert_file_not_contains .stack 'pending_branch=XX-777-stack'

# The unchanged candidate branch in module three must not be pushed or pending.
git --git-dir="$remote_one" show-ref --verify --quiet refs/heads/module-one/XX-777
git --git-dir="$remote_two" show-ref --verify --quiet refs/heads/module-two-XX-777
if git --git-dir="$remote_three" show-ref --verify --quiet refs/heads/XX-777-stack; then
    echo "unchanged candidate module should not be pushed" >&2
    exit 1
fi
if grep -A5 '^\[module "libs/three"\]$' .stack | grep -F 'pending_branch=' >/dev/null; then
    echo "unchanged candidate module should not become pending" >&2
    exit 1
fi

# Any dirty checked-out module blocks upload before manifest state changes.
printf 'dirty\n' >>libs/three/file.txt
if "$GIT_STACK" upload >dirty_upload.out 2>dirty_upload.err; then
    echo "upload should fail when a module has uncommitted changes" >&2
    exit 1
fi
assert_file_contains dirty_upload.err "module libs/three has uncommitted changes"

if "$GIT_STACK" upload --unknown >unknown_upload.out 2>unknown_upload.err; then
    echo "upload should reject unknown options" >&2
    exit 1
fi
assert_file_contains unknown_upload.err "unknown upload option: --unknown"
