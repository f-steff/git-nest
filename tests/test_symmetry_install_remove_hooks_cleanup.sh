#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin symmetry_install_remove_hooks_cleanup

root=$(test_workspace symmetry_install_remove_hooks_cleanup)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
remote_three="$root/remotes/three.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
seed_three="$root/seed/three"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

cd "$outer"

hook_file_for() {
    repo=$1
    hook=$2
    hook_path=$(git -C "$repo" rev-parse --git-path "hooks/$hook")
    case "$hook_path" in
        /*|?:/*) printf '%s\n' "$hook_path" ;;
        *) printf '%s/%s\n' "$repo" "$hook_path" ;;
    esac
}

assert_managed_hooks() {
    repo=$1
    for hook in post-checkout post-commit pre-push; do
        hook_file=$(hook_file_for "$repo" "$hook")
        test -f "$hook_file"
        assert_file_contains "$hook_file" "# git-nest managed hook"
        assert_file_contains "$hook_file" "git-nest"
        assert_file_contains "$hook_file" " snapshot --quiet "
        assert_file_not_contains "$hook_file" " refresh --quiet "
    done
}

assert_no_managed_hooks() {
    repo=$1
    for hook in post-checkout post-commit pre-push; do
        hook_file=$(hook_file_for "$repo" "$hook")
        if [ -f "$hook_file" ]; then
            assert_file_not_contains "$hook_file" "# git-nest managed hook"
        fi
    done
}

"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Install managed hooks through start ." "hooks should be installed in the outer repo and checked-out subprojects."
git checkout -b TRACK-100-outer >/dev/null
git -C libs/one checkout -b one/TRACK-100 >/dev/null
printf 'snapshot\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "TRACK-100 snapshot one" >/dev/null
run_ok "managed hooks installed while recording current state" -- "$GIT_NEST" start . --hooks
assert_managed_hooks "."
assert_managed_hooks libs/one
assert_managed_hooks libs/two

test_step "Propagate hooks to later subprojects" "add and sync should install hooks when the project root already has managed hooks."
run_ok "newly added subproject inherited hooks" -- "$GIT_NEST" add "$remote_three" libs/three
assert_managed_hooks libs/three
sync_hooks="$root/sync_hooks"
mkdir -p "$sync_hooks"
cat >"$sync_hooks/.gitnest" <<EOF
# git-nest manifest

[project]
version=1

[subproject "libs/three"]
repo=$remote_three
target_branch=main
EOF
cd "$sync_hooks"
make_repo "$sync_hooks"
"$GIT_NEST" install-hooks >/dev/null
"$GIT_NEST" sync >/dev/null
assert_managed_hooks "."
assert_managed_hooks libs/three
cd "$outer"

test_step "Use hooks and cleanup branch hints" "managed hooks snapshot pending state, and cleanup commands remove only local branches."
run_ok "install-hooks remained idempotent" -- "$GIT_NEST" install-hooks
git -C libs/two checkout -b two/TRACK-100 >/dev/null
printf 'hook commit\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "TRACK-100 hook snapshot two" >/dev/null
assert_file_contains .gitnest "pending_branch=two/TRACK-100"
merge_sha=$(git -C libs/one rev-parse HEAD)
run_ok "finalize --cleanup removed local pending branch" -- "$GIT_NEST" finalize libs/one --revision "$merge_sha" --cleanup
if git -C libs/one show-ref --verify --quiet refs/heads/one/TRACK-100; then
    echo "finalize --cleanup should delete local pending branch" >&2
    exit 1
fi
git --git-dir="$remote_one" show-ref --verify --quiet refs/heads/main
printf 'keep\n' >libs/one/keep.txt
run_ok "cleanup-branches left unrelated files alone" -- "$GIT_NEST" cleanup-branches
test -f libs/one/keep.txt

test_step "Remove hooks and refuse unmanaged overwrite" "remove-hooks is the inverse of install-hooks, and installation must preflight unmanaged hooks."
run_ok "managed hooks removed" -- "$GIT_NEST" remove-hooks
assert_no_managed_hooks "."
assert_no_managed_hooks libs/one
assert_no_managed_hooks libs/two
assert_no_managed_hooks libs/three
printf '#!/bin/sh\n# unmanaged\n' >"$(hook_file_for libs/one post-commit)"
run_fail "unmanaged hook prevented partial installation" any -- sh -c '"$1" install-hooks >hooks.out 2>hooks.err' sh "$GIT_NEST"
assert_file_contains hooks.err "refusing to overwrite unmanaged hook"
assert_no_managed_hooks "."
assert_no_managed_hooks libs/two
describe_result "install/remove hooks and finalize/cleanup branch behavior stayed symmetric and safe."
