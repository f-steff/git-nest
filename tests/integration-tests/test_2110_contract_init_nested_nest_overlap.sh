#!/bin/sh
# Test: init and absorb-all refuse creating a nest that would swallow an ancestor's subproject

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_init_nested_nest_overlap

# init/init --sure and absorb-all's
# auto-init must refuse creating a new nest whose subtree would contain a
# path already registered as a subproject by an ancestor nest. This can only
# happen if a directory that is an ancestor of an already-registered deep
# subproject is later, retroactively, given its own Git repository -- absorb
# itself cannot hit this (assert_no_deeper_repos and
# assert_path_not_containing_nested_project already guard every absorb path).
test_step "Exercise the nested-nest-overlap refusal and its documented manual recipe" "A retroactively created repository boundary above an already-registered deep subproject must be refused, not silently swallowed into an inconsistent overlapping nest; the refusal must name the conflict and the manual detach/init/absorb recipe must fully resolve it."

root=$(test_workspace contract_init_nested_nest_overlap)
outer="$root/outer"
remote_deep="$root/remotes/deep.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_deep" "$root/seed/deep"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_deep" a/b/c/d >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "add deep subproject" >/dev/null

# Retroactively give an ancestor of the deep subproject its own Git repository --
# the only way this conflict becomes reachable (see section 4).
(cd a/b && git init -q -b main && git_config)

test_step "init --sure refuses to create the overlapping nest" "The refusal must name the new root, the swallowed subproject, the owning ancestor nest, and the exact detach/init/absorb recipe to resolve it manually."
run_fail "init --sure refused inside the retroactive repo boundary" any -- sh -c 'cd a/b && "$1" init --sure >init.out 2>init.err' sh "$GIT_NEST"
assert_file_contains a/b/init.err "would become a nest"
assert_file_contains a/b/init.err "already managed as subproject a/b/c/d"
assert_file_contains a/b/init.err "git-nest detach a/b/c/d"
assert_file_contains a/b/init.err "git-nest absorb c/d"
test ! -f a/b/.gitnest

test_step "absorb-all's auto-init refuses the same overlap, including in --dry-run" "absorb-all must not silently create an inconsistent nest just because it auto-inits on the caller's behalf."
run_fail "absorb-all --sure --dry-run refused inside the retroactive repo boundary" any -- sh -c 'cd a/b && "$1" absorb-all --sure --dry-run >dryrun.out 2>dryrun.err' sh "$GIT_NEST"
assert_file_contains a/b/dryrun.err "would become a nest"
test ! -f a/b/.gitnest
run_fail "absorb-all --sure refused inside the retroactive repo boundary" any -- sh -c 'cd a/b && "$1" absorb-all --sure >real.out 2>real.err' sh "$GIT_NEST"
assert_file_contains a/b/real.err "would become a nest"
test ! -f a/b/.gitnest

test_step "The documented manual recipe fully resolves the conflict" "Detach the conflicting subproject from the ancestor nest, retry init here, then absorb the checkout back into the new nest."
"$GIT_NEST" detach a/b/c/d >/dev/null
assert_file_not_contains .gitnest '[subproject "a/b/c/d"]'
(cd a/b && "$GIT_NEST" init --sure >/dev/null)
test -f a/b/.gitnest
(cd a/b && "$GIT_NEST" absorb c/d >/dev/null)
assert_file_contains a/b/.gitnest '[subproject "c/d"]'
test -d a/b/c/d/.git
git -C a/b/c/d rev-parse HEAD >/dev/null

describe_result "init --sure and absorb-all both refused the overlapping nest with a specific, actionable error, and the documented manual detach/init/absorb recipe fully resolved it end to end."
