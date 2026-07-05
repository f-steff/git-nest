#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin sync_stale_subprojects

root=$(test_workspace sync_stale_subprojects)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
remote_shared="$root/remotes/shared.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
seed_shared="$root/seed/shared"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_shared" "$seed_shared"

project="$root/project"
make_repo "$project"
cd "$project"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote_one" old/one >/dev/null
"$GIT_LEGO" add "$remote_two" remove/two >/dev/null
test -d old/one/.git
test -d remove/two/.git

# A clean subproject path move should relocate the existing checkout before sync
# fetches/checks out the manifest state.
revision_one=$(git -C old/one rev-parse HEAD)
cat >.gitlego <<EOF
# git-lego manifest

[project]
version=1

[subproject "new/one"]
repo=$remote_one
target_branch=main
revision=$revision_one
EOF
"$GIT_LEGO" sync >move.out 2>move.err
test -d new/one/.git
test ! -e old/one
test ! -e remove/two
assert_file_contains move.err "Notice: moved stale subproject old/one to new/one"
assert_file_contains move.err "Notice: removed stale subproject remove/two because it is no longer in .gitlego"

# Dirty stale subprojects are left in place, and the warning explains --prune.
"$GIT_LEGO" add "$remote_two" dirty/two >/dev/null
printf 'local\n' >dirty/two/local.txt
cat >.gitlego <<EOF
# git-lego manifest

[project]
version=1

[subproject "new/one"]
repo=$remote_one
target_branch=main
revision=$revision_one
EOF
"$GIT_LEGO" sync >dirty.out 2>dirty.err
test -d dirty/two/.git
assert_file_contains dirty.err "Warning: stale subproject dirty/two has local changes or untracked files"
assert_file_contains dirty.err "git-lego sync --prune"
"$GIT_LEGO" sync --prune >prune.out 2>prune.err
test ! -e dirty/two
assert_file_contains prune.err "Notice: removed stale subproject dirty/two with --prune despite local state"

# A local-only branch tip is also kept until the user confirms cleanup.
"$GIT_LEGO" add "$remote_two" branch/two >/dev/null
git -C branch/two checkout -b local-only >/dev/null
printf 'branch\n' >branch/two/branch.txt
git -C branch/two add branch.txt
git -C branch/two commit -m "local-only branch" >/dev/null
cat >.gitlego <<EOF
# git-lego manifest

[project]
version=1

[subproject "new/one"]
repo=$remote_one
target_branch=main
revision=$revision_one
EOF
"$GIT_LEGO" sync >branch.out 2>branch.err
test -d branch/two/.git
assert_file_contains branch.err "Warning: stale subproject branch/two has local-only branch tip local-only"
assert_file_contains branch.err "git-lego sync --prune"
"$GIT_LEGO" sync --prune >branch_prune.out 2>branch_prune.err
test ! -e branch/two

# Ambiguous same-repo moves are never pruned automatically or suggested.
"$GIT_LEGO" add "$remote_shared" ambig/old >/dev/null
revision_shared=$(git -C ambig/old rev-parse HEAD)
cat >.gitlego <<EOF
# git-lego manifest

[project]
version=1

[subproject "ambig/new-one"]
repo=$remote_shared
target_branch=main
revision=$revision_shared

[subproject "ambig/new-two"]
repo=$remote_shared
target_branch=main
revision=$revision_shared
EOF
"$GIT_LEGO" sync >ambig.out 2>ambig.err || true
test -d ambig/old/.git
test -d ambig/new-one/.git
test -d ambig/new-two/.git
assert_file_contains ambig.err "Warning: stale subproject ambig/old could match multiple paths"
assert_file_not_contains ambig.err "git-lego sync --prune"
