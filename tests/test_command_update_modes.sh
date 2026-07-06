#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_update_modes

test_step "Exercise command update modes" "This test verifies the documented command update modes behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_update_modes)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

# Updating to target head should fetch origin/main, check it out, and rewrite revision.
printf 'second\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "second" >/dev/null
git -C "$seed" push origin main >/dev/null
second=$(git -C "$seed" rev-parse HEAD)

"$GIT_LEGO" update libs/foo --target-head >/dev/null
test "$(git -C libs/foo rev-parse HEAD)" = "$second"
assert_file_contains .gitlego "revision=$second"
assert_file_not_contains .gitlego "tag="

# Updating to a tag should record both tag and resolved revision.
git -C "$seed" tag v2.0.0 "$second"
git -C "$seed" push origin v2.0.0 >/dev/null
"$GIT_LEGO" update libs/foo --tag v2.0.0 >/dev/null
test "$(git -C libs/foo rev-parse HEAD)" = "$second"
assert_file_contains .gitlego "tag=v2.0.0"
assert_file_contains .gitlego "revision=$second"

# Updating to an explicit revision should remove tag state and pin the SHA.
printf 'third\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "third" >/dev/null
git -C "$seed" push origin main >/dev/null
third=$(git -C "$seed" rev-parse HEAD)

"$GIT_LEGO" update libs/foo --revision "$third" >/dev/null
test "$(git -C libs/foo rev-parse HEAD)" = "$third"
assert_file_contains .gitlego "revision=$third"
assert_file_not_contains .gitlego "tag=v2.0.0"

# --no-fetch should use only refs already present in the subproject checkout.
printf 'fourth\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "fourth" >/dev/null
git -C "$seed" push origin main >/dev/null
fourth=$(git -C "$seed" rev-parse HEAD)

"$GIT_LEGO" update libs/foo --remote --no-fetch >/dev/null
test "$(git -C libs/foo rev-parse HEAD)" = "$third"
assert_file_contains .gitlego "revision=$third"

# --remote is an alias for --target-head and should fetch before resolving.
"$GIT_LEGO" update libs/foo --remote >/dev/null
test "$(git -C libs/foo rev-parse HEAD)" = "$fourth"
assert_file_contains .gitlego "revision=$fourth"

# Branch retargeting records a new target branch and pins that branch head.
git -C "$seed" checkout -b release/1 >/dev/null
printf 'release\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "release branch" >/dev/null
git -C "$seed" push origin release/1 >/dev/null
release=$(git -C "$seed" rev-parse HEAD)
git -C "$seed" checkout main >/dev/null

"$GIT_LEGO" update libs/foo --set-branch release/1 --remote >/dev/null
test "$(git -C libs/foo rev-parse HEAD)" = "$release"
assert_file_contains .gitlego "target_branch=release/1"
assert_file_contains .gitlego "revision=$release"

if "$GIT_LEGO" update libs/foo --branch release/1 --tag v2.0.0 >branch_tag.out 2>branch_tag.err; then
    echo "update should reject branch retargeting with tag pinning" >&2
    exit 1
fi
assert_file_contains branch_tag.err "cannot be combined with --tag"

git -C "$seed" tag v3.0.0 "$release"
git -C "$seed" push origin v3.0.0 >/dev/null
if "$GIT_LEGO" update libs/foo --tag v3.0.0 --no-fetch >no_fetch_tag.out 2>no_fetch_tag.err; then
    echo "update --no-fetch should fail for an unfetched tag" >&2
    exit 1
fi
assert_file_contains no_fetch_tag.err "does not resolve"

# Dirty subprojects must be cleaned before update so checkout and manifest stay aligned.
printf 'dirty\n' >>libs/foo/file.txt
if "$GIT_LEGO" update libs/foo --target-head >dirty.out 2>dirty.err; then
    echo "update should fail on dirty subprojects" >&2
    exit 1
fi
assert_file_contains dirty.err "uncommitted changes"
git -C libs/foo checkout -- file.txt

# Pending subprojects must be finalized or cleared before update rewrites version state.
git -C libs/foo checkout -b UPD-100-subproject >/dev/null
printf 'pending\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "UPD-100 pending" >/dev/null
"$GIT_LEGO" upload >/dev/null
if "$GIT_LEGO" update libs/foo --target-head >pending.out 2>pending.err; then
    echo "update should fail on pending subprojects" >&2
    exit 1
fi
assert_file_contains pending.err "is pending on branch"

describe_result "The command update modes behavior matched the expected command output and repository state."
