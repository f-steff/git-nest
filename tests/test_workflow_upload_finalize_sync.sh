#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_upload_finalize_sync

test_step "Exercise workflow upload finalize sync" "This test verifies the documented workflow upload finalize sync behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace workflow_upload_finalize_sync)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer_remote="$work/remotes/outer.git"
outer="$work/outer"
clone="$work/clone"
direct_remote="$work/remotes/direct.git"
direct_seed="$work/seed/direct"
direct_outer="$work/direct_outer"

# Create a subproject remote, an outer repo, and an outer bare remote for push tests.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"
git -C "$outer" init --bare "$outer_remote" >/dev/null
git -C "$outer" remote add origin "$outer_remote"

# Initialize the workspace and publish the initial outer main branch.
cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
git push -u origin main >/dev/null

# Commit subproject work, upload it, and verify pending metadata was recorded.
"$GIT_NEST" start XX-123-short-description >/dev/null
printf 'change\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "XX-123 subproject change" >/dev/null
"$GIT_NEST" upload >/dev/null

assert_file_contains .gitnest 'pending_branch=XX-123-short-description'
assert_file_contains .gitnest 'base_revision='
assert_file_contains .gitnest 'pushed_commit='

# Finalize by tag and verify the pending state is replaced with pinned state.
merge_sha=$(git -C libs/foo rev-parse HEAD)
tag_name=v1.0.0
git -C libs/foo tag "$tag_name" "$merge_sha"
git -C libs/foo push origin "$tag_name" >/dev/null
"$GIT_NEST" finalize libs/foo --tag "$tag_name" >/dev/null
assert_file_contains .gitnest "tag=$tag_name"
assert_file_contains .gitnest "revision=$merge_sha"
if grep -F 'pending_branch=' .gitnest >/dev/null; then
    echo "pending state remained after finalize" >&2
    exit 1
fi

# Sync from only the manifest to prove finalized tags/revisions restore subprojects.
mkdir -p "$clone"
cp .gitnest "$clone/.gitnest"
cd "$clone"
"$GIT_NEST" sync >/dev/null
test -d libs/foo/.git
test "$(git -C libs/foo rev-parse HEAD)" = "$merge_sha"

# Direct finalize upload pushes subproject work and records the pushed commit as
# finalized without leaving pending review state.
mkdir -p "$work/seed"
make_bare_remote "$direct_remote" "$direct_seed"
make_repo "$direct_outer"
cd "$direct_outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$direct_remote" libs/direct >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial direct workspace" >/dev/null
"$GIT_NEST" start DIRECT-100-finalize >/dev/null
git -C libs/direct checkout -b direct/DIRECT-100 >/dev/null
printf 'direct\n' >>libs/direct/file.txt
git -C libs/direct add file.txt
git -C libs/direct commit -m "DIRECT-100 direct finalize" >/dev/null
direct_sha=$(git -C libs/direct rev-parse HEAD)

"$GIT_NEST" upload --finalize >/dev/null
git --git-dir="$direct_remote" show-ref --verify --quiet refs/heads/direct/DIRECT-100
assert_file_contains .gitnest "revision=$direct_sha"
assert_file_contains .gitnest "finalized_from_branch=direct/DIRECT-100"
assert_file_not_contains .gitnest "pending_branch="
assert_file_not_contains .gitnest "base_revision="
assert_file_not_contains .gitnest "pushed_commit="
"$GIT_NEST" no-pending >direct_no_pending.out
assert_file_contains direct_no_pending.out "No pending subprojects."

describe_result "The workflow upload finalize sync behavior matched the expected command output and repository state."
