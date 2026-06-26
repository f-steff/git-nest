#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin auto_finalize_and_check

work=$(test_workspace auto_finalize)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

# Build a single-module workspace used to exercise pending check and auto-finalize.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

# Create pending module work through the normal start/upload flow.
cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote" libs/foo >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null
"$GIT_STACK" start XX-321-auto-finalize >/dev/null

printf 'change\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "XX-321 module change" >/dev/null
"$GIT_STACK" upload >/dev/null

# check is the outer merge gate and must fail while pending entries remain.
if "$GIT_STACK" check >/dev/null 2>&1; then
    echo "check should fail while pending entries exist" >&2
    exit 1
fi

# Simulate the module PR landing on main with an identifiable ticket commit.
git -C libs/foo checkout main >/dev/null
git -C libs/foo merge --ff-only XX-321-auto-finalize >/dev/null
git -C libs/foo push origin main >/dev/null
git -C libs/foo checkout XX-321-auto-finalize >/dev/null

# Auto-finalize should find exactly one target-branch commit with the ticket key.
"$GIT_STACK" finalize libs/foo >/dev/null
if grep -F 'pending_branch=' .stack >/dev/null; then
    echo "auto finalize did not remove pending state" >&2
    exit 1
fi
