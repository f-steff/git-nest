#!/bin/sh
# Test: foreach-clean git pull --ff-only updates clean subprojects on their branch, skips dirty ones, and reports non-fast-forward

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_foreach_pull_current_branch

work=$(test_workspace workflow_foreach_pull_current_branch)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed" "$work/scratch"
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

# Push a new commit onto a bare remote's main branch through a throwaway clone,
# so a subproject checked out from that remote falls behind its upstream.
advance_remote() {
    remote=$1
    scratch=$2
    marker=$3
    git clone "$remote" "$scratch" >/dev/null 2>&1
    (
        cd "$scratch"
        git_config
        printf '%s\n' "$marker" >>file.txt
        git add file.txt
        git commit -m "$marker" >/dev/null
        git push origin main >/dev/null
    )
    rm -rf "$scratch"
}

test_step "Advance every remote and dirty one subproject" "foreach-clean should fast-forward clean subprojects that are behind and leave dirty ones untouched."
advance_remote "$remote_one" "$work/scratch/one" advance-one
advance_remote "$remote_two" "$work/scratch/two" advance-two
advance_remote "$remote_three" "$work/scratch/three" advance-three
printf 'local uncommitted edit\n' >>libs/two/file.txt

test_step "Fan out a fast-forward-only pull over clean subprojects" "clean subprojects on a branch should fast-forward; the dirty subproject should be skipped."
run_ok "foreach-clean pulled the clean subprojects fast-forward-only" -- "$GIT_NEST" foreach-clean -- git pull --ff-only
assert_file_contains libs/one/file.txt advance-one
assert_file_contains libs/three/file.txt advance-three
# libs/two was dirty, so foreach-clean skipped it: the remote commit is absent.
assert_file_not_contains libs/two/file.txt advance-two
assert_file_contains libs/two/file.txt "local uncommitted edit"

test_step "Diverge a clean subproject and advance its remote" "a non-fast-forwardable branch must be reported, not merged."
(
    cd libs/three
    printf 'local committed change\n' >>file.txt
    git add file.txt
    git commit -m "local-three" >/dev/null
)
advance_remote "$remote_three" "$work/scratch/three2" advance-three-2

test_step "Fan out again with --continue-on-error" "the diverged subproject should fail fast-forward while others stay clean, and the recipe should report a non-zero status."
set +e
"$GIT_NEST" foreach-clean --continue-on-error -- git pull --ff-only >pull_diverged.out 2>pull_diverged.err
pull_rc=$?
set -e
[ "$pull_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: expected non-fast-forward pull to report a non-zero status, got 0\n' >&2
    exit 1
}
# The diverged subproject kept its local commit and did NOT absorb the second remote advance.
assert_file_contains libs/three/file.txt "local committed change"
assert_file_not_contains libs/three/file.txt advance-three-2

describe_result "foreach-clean fast-forwarded clean subprojects on their branch, skipped the dirty subproject, and reported the diverged subproject without merging."
