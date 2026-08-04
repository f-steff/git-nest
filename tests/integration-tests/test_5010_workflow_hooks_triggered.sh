#!/bin/sh
# Test: installed hooks fire on real Git checkout, commit, and push

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_hooks_triggered

# Installing hooks is not enough; the hooks must actually run when Git performs
# checkouts, commits, and pushes. This exercises every managed hook through real
# Git operations and asserts the observable effect of each.
test_step "Install hooks and trigger every one with real Git operations" "Root post-checkout must print restore guidance, subproject pre-push must record a push candidate, root pre-commit must refresh the manifest via snapshot, root pre-push must warn when the nest is not reproducible, and subproject post-checkout must not block a checkout."

root=$(test_workspace workflow_hooks_triggered)
foo_remote="$root/remotes/foo.git"
nest_remote="$root/remotes/nest.git"
outer="$root/outer"

mkdir -p "$root/remotes"
make_bare_remote "$foo_remote" "$root/seed/foo"
# A bare remote for the nest root so root pre-push has somewhere to push.
git init -q --bare --initial-branch=main "$nest_remote" >/dev/null 2>&1 ||
    git init -q --bare "$nest_remote" >/dev/null
git -C "$nest_remote" symbolic-ref HEAD refs/heads/main 2>/dev/null || true

make_repo "$outer"
cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$foo_remote" libs/foo >/dev/null
git remote add origin "$nest_remote"
git add .gitnest .gitignore .gitattributes
git commit -m "initial nest" >/dev/null
git push -u origin main >/dev/null 2>&1

"$GIT_NEST" hooks-install >/dev/null

# --- Root post-checkout: prints restore guidance on checkout ---
test_step "Root post-checkout fires on git checkout" "A branch checkout at the nest root should print git-nest restore guidance."
git checkout -b feature >post_checkout.out 2>&1 || true
assert_file_contains post_checkout.out "git-nest restore"
git checkout main >/dev/null 2>&1 || true

# --- Subproject pre-push: records a push candidate on push ---
test_step "Subproject pre-push fires on git push" "Pushing a subproject should record a push candidate in .gitnest-push-candidates at the nest root."
git -C libs/foo commit --allow-empty -m "advance foo" >/dev/null
git -C libs/foo push origin HEAD:main >sub_push.out 2>&1 || true
test -f .gitnest-push-candidates
assert_file_contains .gitnest-push-candidates "libs/foo"

# --- Root pre-commit: refreshes the manifest via snapshot ---
test_step "Root pre-commit fires on git commit" "Committing at the nest root should snapshot the now-reproducible subproject and warn that .gitnest changed."
foo_head=$(git -C libs/foo rev-parse HEAD)
git commit --allow-empty -m "trigger pre-commit" >pre_commit.out 2>&1 || true
assert_file_contains .gitnest "revision=$foo_head"
assert_file_contains pre_commit.out "review and stage"
# Record the refreshed manifest so the working tree is clean for the next push.
git add .gitnest
git commit -m "record refreshed manifest" >/dev/null

# --- Root pre-push: warns when the nest is not reproducible ---
test_step "Root pre-push fires on git push" "A local-only subproject commit makes the nest unreproducible; pushing the root should warn without blocking."
git -C libs/foo commit --allow-empty -m "local only, unpushed" >/dev/null
git push origin main >root_push.out 2>&1 || true
assert_file_contains root_push.out "not fully reproducible"

# --- Subproject post-checkout: runs without blocking the checkout ---
test_step "Subproject post-checkout fires without blocking" "A checkout inside a subproject triggers its snapshot hook but must still complete."
git -C libs/foo checkout -b sidebranch >sub_checkout.out 2>&1 || true
git -C libs/foo rev-parse --abbrev-ref HEAD >sub_branch.out
assert_file_contains sub_branch.out "sidebranch"

describe_result "Every managed hook fired through real Git operations with the expected observable effect."
