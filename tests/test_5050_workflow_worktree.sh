#!/bin/sh
# Test: git-nest is transparent to Git worktrees

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_worktree

test_step "Create a main worktree with a nest and one subproject" "This verifies git-nest init and add work normally in a standard repository."
root=$(test_workspace workflow_worktree)
remote="$root/remotes/sub.git"
seed="$root/seed/sub"
outer="$root/main"
mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"
cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote" libs/sub >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Create a linked worktree with git worktree add" "A consumer may have multiple branches checked out via worktrees; git-nest should work inside each one."
linked="$root/linked"
run_ok "linked worktree created" -- git -C "$outer" worktree add -b linked-worktree "$linked" main
cd "$linked"

test_step "Run status and restore from the linked worktree" "git-nest commands must function normally inside a linked worktree."
run_ok "status from linked worktree" -- "$GIT_NEST" status
run_ok "restore from linked worktree" -- "$GIT_NEST" restore
test -d "$linked/libs/sub/.git"

test_step "Verify operations in the linked worktree don't affect the main worktree" "Each worktree maintains separate subproject checkouts, so the main tree's checkout must remain intact and independent."
test -d "$outer/libs/sub/.git"
test -d "$linked/libs/sub/.git"
main_sub_wt=$(cd "$outer/libs/sub" && git rev-parse --show-toplevel)
linked_sub_wt=$(cd "$linked/libs/sub" && git rev-parse --show-toplevel)
test "$main_sub_wt" != "$linked_sub_wt"
describe_result "Main subproject worktree: $main_sub_wt; linked subproject worktree: $linked_sub_wt (different directories)"

test_step "Verify materialized_state path is worktree-specific" "The materialized state file uses git rev-parse --git-path, which resolves to the worktree's private git directory."
main_state=$(cd "$outer" && git rev-parse --git-path git-nest/subprojects)
linked_state=$(cd "$linked" && git rev-parse --git-path git-nest/subprojects)
test "$main_state" != "$linked_state"
describe_result "Main state: $main_state; linked state: $linked_state (different paths)"

test_step "Verify version and help work from the linked worktree" "Non-manifest commands like version and help must also work inside linked worktrees."
run_ok "version from linked worktree" -- "$GIT_NEST" version
run_ok "help from linked worktree" -- "$GIT_NEST" --help

describe_result "git-nest is fully transparent to Git worktrees: each tree has its own independent state, checkouts, and materialized state path."
