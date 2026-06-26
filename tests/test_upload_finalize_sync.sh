#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin upload_finalize_sync

work=$(test_workspace upload_finalize_sync)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer_remote="$work/remotes/outer.git"
outer="$work/outer"
clone="$work/clone"
direct_remote="$work/remotes/direct.git"
direct_seed="$work/seed/direct"
direct_outer="$work/direct_outer"

# Create a module remote, an outer repo, and an outer bare remote for push tests.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"
git -C "$outer" init --bare "$outer_remote" >/dev/null
git -C "$outer" remote add origin "$outer_remote"

# Initialize the workspace and publish the initial outer main branch.
cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote" libs/foo >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null
git push -u origin main >/dev/null

# Commit module work, upload it, and verify pending metadata was recorded.
"$GIT_STACK" start XX-123-short-description >/dev/null
printf 'change\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "XX-123 module change" >/dev/null
"$GIT_STACK" upload >/dev/null

assert_file_contains .stack 'pending_branch=XX-123-short-description'
assert_file_contains .stack 'base_revision='
assert_file_contains .stack 'pushed_commit='

# Finalize by tag and verify the pending state is replaced with pinned state.
merge_sha=$(git -C libs/foo rev-parse HEAD)
tag_name=v1.0.0
git -C libs/foo tag "$tag_name" "$merge_sha"
git -C libs/foo push origin "$tag_name" >/dev/null
"$GIT_STACK" finalize libs/foo --tag "$tag_name" >/dev/null
assert_file_contains .stack "tag=$tag_name"
assert_file_contains .stack "revision=$merge_sha"
if grep -F 'pending_branch=' .stack >/dev/null; then
    echo "pending state remained after finalize" >&2
    exit 1
fi

# Sync from only the manifest to prove finalized tags/revisions restore modules.
mkdir -p "$clone"
cp .stack "$clone/.stack"
cd "$clone"
"$GIT_STACK" sync >/dev/null
test -d libs/foo/.git
test "$(git -C libs/foo rev-parse HEAD)" = "$merge_sha"

# Direct finalize upload pushes module work and records the pushed commit as
# finalized without leaving pending review state.
mkdir -p "$work/seed"
make_bare_remote "$direct_remote" "$direct_seed"
make_repo "$direct_outer"
cd "$direct_outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$direct_remote" libs/direct >/dev/null
git add .stack .gitignore
git commit -m "initial direct workspace" >/dev/null
"$GIT_STACK" start DIRECT-100-finalize >/dev/null
git -C libs/direct checkout -b direct/DIRECT-100 >/dev/null
printf 'direct\n' >>libs/direct/file.txt
git -C libs/direct add file.txt
git -C libs/direct commit -m "DIRECT-100 direct finalize" >/dev/null
direct_sha=$(git -C libs/direct rev-parse HEAD)

"$GIT_STACK" upload --finalize >/dev/null
git --git-dir="$direct_remote" show-ref --verify --quiet refs/heads/direct/DIRECT-100
assert_file_contains .stack "revision=$direct_sha"
assert_file_contains .stack "finalized_from_branch=direct/DIRECT-100"
assert_file_not_contains .stack "pending_branch="
assert_file_not_contains .stack "base_revision="
assert_file_not_contains .stack "pushed_commit="
"$GIT_STACK" check >direct_check.out
assert_file_contains direct_check.out "No pending modules."
