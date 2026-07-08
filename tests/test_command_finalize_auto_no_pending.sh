#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_finalize_auto_no_pending

test_step "Exercise command finalize auto no pending" "This test verifies the documented command finalize auto no pending behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace command_finalize_auto_no_pending)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

# Build a single-subproject workspace used to exercise pending no-pending and auto-finalize.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

# Create pending subproject work through the normal start/upload flow.
cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
"$GIT_NEST" start XX-321-auto-finalize >/dev/null

printf 'change\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "XX-321 subproject change" >/dev/null
"$GIT_NEST" upload >/dev/null

# no-pending is the outer merge gate and must fail while pending entries remain.
if "$GIT_NEST" no-pending >/dev/null 2>&1; then
    echo "no-pending should fail while pending entries exist" >&2
    exit 1
fi

# Simulate the subproject PR landing on main with an identifiable ticket commit.
git -C libs/foo checkout main >/dev/null
git -C libs/foo merge --ff-only XX-321-auto-finalize >/dev/null
git -C libs/foo push origin main >/dev/null
git -C libs/foo checkout XX-321-auto-finalize >/dev/null

# Auto-finalize should find exactly one target-branch commit with the ticket key.
"$GIT_NEST" finalize libs/foo >/dev/null
if grep -F 'pending_branch=' .gitnest >/dev/null; then
    echo "auto finalize did not remove pending state" >&2
    exit 1
fi

describe_result "The command finalize auto no pending behavior matched the expected command output and repository state."
