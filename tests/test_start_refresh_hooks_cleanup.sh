#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin start_refresh_hooks_cleanup

root=$(test_workspace start_refresh_hooks_cleanup)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
remote_three="$root/remotes/three.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
seed_three="$root/seed/three"
outer="$root/outer"

# Build a two-module workspace for dirty preflight, hooks, and cleanup behavior.
mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

cd "$outer"

# Resolve hook paths the same way the implementation does for outer/modules.
hook_file_for() {
    repo=$1
    hook=$2
    hook_path=$(git -C "$repo" rev-parse --git-path "hooks/$hook")
    case "$hook_path" in
        /*|?:/*) printf '%s\n' "$hook_path" ;;
        *) printf '%s/%s\n' "$repo" "$hook_path" ;;
    esac
}

# Assert that all managed hook types exist and contain the git-stack marker.
assert_managed_hooks() {
    repo=$1
    for hook in post-checkout post-commit pre-push; do
        hook_file=$(hook_file_for "$repo" "$hook")
        test -f "$hook_file"
        assert_file_contains "$hook_file" "# git-stack managed hook"
        assert_file_contains "$hook_file" " refresh --quiet "
    done
}

# Assert no managed hooks remain; unmanaged hooks may still exist.
assert_no_managed_hooks() {
    repo=$1
    for hook in post-checkout post-commit pre-push; do
        hook_file=$(hook_file_for "$repo" "$hook")
        if [ -f "$hook_file" ]; then
            assert_file_not_contains "$hook_file" "# git-stack managed hook"
        fi
    done
}

# Initialize the workspace with two checked-out modules.
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote_one" libs/one >/dev/null
"$GIT_STACK" add "$remote_two" libs/two >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null

# --cancel-dirty must stop before any branch switching occurs.
printf 'dirty\n' >>libs/one/file.txt
before_outer=$(git branch --show-current)
before_one=$(git -C libs/one branch --show-current)
if "$GIT_STACK" start --cancel-dirty XX-888-dirty >cancel.out 2>cancel.err; then
    echo "start --cancel-dirty should fail when modules are dirty" >&2
    exit 1
fi
test "$(git branch --show-current)" = "$before_outer"
test "$(git -C libs/one branch --show-current)" = "$before_one"
assert_file_contains cancel.err "start canceled"

# --stash-dirty should stash module changes and then switch all repos.
"$GIT_STACK" start --stash-dirty XX-888-dirty >/dev/null
test "$(git branch --show-current)" = "XX-888-dirty"
test "$(git -C libs/one branch --show-current)" = "XX-888-dirty"
test -z "$(git -C libs/one status --porcelain)"
git -C libs/one stash list | grep "git-stack start preflight" >/dev/null

# --discard-dirty resets tracked edits but refuses to remove untracked files.
git -C libs/two checkout main >/dev/null
printf 'tracked\n' >>libs/two/file.txt
printf 'untracked\n' >libs/two/untracked.txt
if "$GIT_STACK" start --discard-dirty XX-999-discard >discard.out 2>discard.err; then
    echo "start --discard-dirty should fail when untracked files remain" >&2
    exit 1
fi
assert_file_contains discard.err "still has untracked files"
test -f libs/two/untracked.txt
rm -f libs/two/untracked.txt
test -z "$(git -C libs/two status --porcelain)"

# start . refreshes current branch layout and installs hooks without switching modules.
git checkout -b TRACK-100-outer >/dev/null
git -C libs/one checkout -b one/TRACK-100 >/dev/null
printf 'refresh\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "TRACK-100 refresh one" >/dev/null
"$GIT_STACK" start . --hooks >/dev/null
assert_file_contains .stack "branch=TRACK-100-outer"
assert_file_contains .stack "pending_branch=one/TRACK-100"
test "$(git -C libs/two branch --show-current)" = "main"

assert_managed_hooks "."
assert_managed_hooks libs/one
assert_managed_hooks libs/two

# Newly added modules inherit managed hooks when the stack root has them.
"$GIT_STACK" add "$remote_three" libs/three >/dev/null
assert_managed_hooks libs/three

# Missing modules cloned by sync inherit managed hooks when the stack root has them.
sync_hooks="$root/sync_hooks"
mkdir -p "$sync_hooks"
cat >"$sync_hooks/.stack" <<EOF
# git-stack manifest

[stack]

[module "libs/three"]
repo=$remote_three
target_branch=main
EOF
cd "$sync_hooks"
make_repo "$sync_hooks"
"$GIT_STACK" install-hooks >/dev/null
"$GIT_STACK" sync >/dev/null
assert_managed_hooks "."
assert_managed_hooks libs/three
cd "$outer"

# install-hooks is idempotent and covers the same outer/module target set.
"$GIT_STACK" install-hooks >/dev/null
assert_managed_hooks "."
assert_managed_hooks libs/one
assert_managed_hooks libs/two
assert_managed_hooks libs/three

# A managed post-commit hook should update manifest pending state through refresh --quiet.
git -C libs/two checkout -b two/TRACK-100 >/dev/null
printf 'hook commit\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "TRACK-100 hook refresh two" >/dev/null
assert_file_contains .stack "pending_branch=two/TRACK-100"

# finalize --cleanup deletes the local pending branch but leaves remotes alone.
merge_sha=$(git -C libs/one rev-parse HEAD)
"$GIT_STACK" finalize libs/one --revision "$merge_sha" --cleanup >/dev/null
if git -C libs/one show-ref --verify --quiet refs/heads/one/TRACK-100; then
    echo "finalize --cleanup should delete local pending branch" >&2
    exit 1
fi
git --git-dir="$remote_one" show-ref --verify --quiet refs/heads/main
printf 'keep\n' >libs/one/keep.txt

# cleanup-branches is idempotent and must not delete unrelated files.
"$GIT_STACK" cleanup-branches >/dev/null
test -f libs/one/keep.txt

# remove-hooks removes only managed hooks from outer and modules.
"$GIT_STACK" remove-hooks >/dev/null
assert_no_managed_hooks "."
assert_no_managed_hooks libs/one
assert_no_managed_hooks libs/two
assert_no_managed_hooks libs/three

# Installation preflights every target and refuses to partially overwrite unmanaged hooks.
printf '#!/bin/sh\n# unmanaged\n' >"$(hook_file_for libs/one post-commit)"
if "$GIT_STACK" install-hooks >hooks.out 2>hooks.err; then
    echo "install-hooks should refuse unmanaged hooks" >&2
    exit 1
fi
assert_file_contains hooks.err "refusing to overwrite unmanaged hook"
assert_no_managed_hooks "."
assert_no_managed_hooks libs/two
