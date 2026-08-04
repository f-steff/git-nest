#!/bin/sh
# Test: restore materializes a copied manifest, re-clones missing checkouts, and aggregates partial failures

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_restore_materialize

test_step "Exercise restore materialization and failure handling" "restore must clone and check out recorded revisions from a copied manifest in a plain folder, re-clone a deleted checkout, and on a partial failure restore the good subprojects while reporting the bad one and exiting nonzero."

root=$(test_workspace command_restore_materialize)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
mkdir -p "$root/remotes"
make_bare_remote "$remote_one" "$root/seed/one"
make_bare_remote "$remote_two" "$root/seed/two"
url_one="file://$remote_one"
url_two="file://$remote_two"
rev_one=$(git --git-dir="$remote_one" rev-parse HEAD)
rev_two=$(git --git-dir="$remote_two" rev-parse HEAD)

# --- Copied-manifest startup in a plain (non-Git) empty folder ---
test_step "Restore a copied manifest in a plain folder" "Dropping .gitnest into an empty directory and running restore should clone each subproject and check out its recorded revision, and exit cleanly even without an outer Git repository."
materialize="$root/materialize"
mkdir -p "$materialize"
cat >"$materialize/.gitnest" <<EOF
[project]
version=1

[subproject "libs/one"]
repo=$url_one
target_branch=main
revision=$rev_one

[subproject "libs/two"]
repo=$url_two
target_branch=main
revision=$rev_two
EOF
cd "$materialize"
run_ok "copied manifest restored into a plain folder" -- "$GIT_NEST" restore
test -d libs/one/.git
test -d libs/two/.git
test "$(git -C libs/one rev-parse HEAD)" = "$rev_one"
test "$(git -C libs/two rev-parse HEAD)" = "$rev_two"

# --- Re-clone a deleted checkout ---
test_step "Restore re-clones a deleted checkout" "Removing a subproject checkout and running restore should re-clone it at the recorded revision."
rm -rf libs/one
test ! -e libs/one
run_ok "deleted checkout re-cloned" -- "$GIT_NEST" restore
test -d libs/one/.git
test "$(git -C libs/one rev-parse HEAD)" = "$rev_one"

# --- Partial failure: good subprojects restored, bad one reported, nonzero exit ---
test_step "Restore aggregates partial failures" "With one unreachable remote, restore should restore the reachable subprojects, report the failing one, and exit nonzero."
partial="$root/partial"
mkdir -p "$partial"
cat >"$partial/.gitnest" <<EOF
[project]
version=1

[subproject "good/one"]
repo=$url_one
target_branch=main
revision=$rev_one

[subproject "bad/two"]
repo=file://$root/remotes/does-not-exist.git
target_branch=main
revision=$rev_two
EOF
cd "$partial"
if "$GIT_NEST" restore >partial.out 2>partial.err; then
    printf 'UNEXPECTED RESULT: restore should exit nonzero on a partial failure\n' >&2
    exit 1
fi
# The reachable subproject is still restored.
test -d good/one/.git
test "$(git -C good/one rev-parse HEAD)" = "$rev_one"
# The failing subproject is reported with recovery guidance.
assert_file_contains partial.err "restore failed for one or more subprojects"
assert_file_contains partial.err "bad/two"
assert_file_contains partial.err "git-nest verify"

describe_result "restore materialized a copied manifest, re-cloned a deleted checkout, and handled a partial failure by restoring good subprojects while reporting the bad one and exiting nonzero."
