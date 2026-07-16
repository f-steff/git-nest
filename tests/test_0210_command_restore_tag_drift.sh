#!/bin/sh
# Test: restore protects a pinned tag by default and proceeds only with --force

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_restore_tag_drift

root=$(test_workspace command_restore_tag_drift)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Pin a subproject by tag and revision" "restore must detect when a remote tag moves away from the recorded revision."
git -C "$seed" tag -f v-drift "$(git -C "$seed" rev-parse HEAD)" >/dev/null
git -C "$seed" push -f origin v-drift >/dev/null
run_ok "tag pin recorded in the manifest" -- "$GIT_NEST" update libs/foo --tag v-drift
recorded=$(sed -n 's/^revision=//p' .gitnest | sed -n '1p')
head_before=$(git -C libs/foo rev-parse HEAD)

test_step "Move the remote tag after it was pinned" "a moved tag should not silently change the checked-out source."
printf 'drift\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "move drift tag" >/dev/null
git -C "$seed" tag -f v-drift HEAD >/dev/null
git -C "$seed" push -f origin v-drift >/dev/null
run_fail "tag/revision drift rejected before checkout" any -- sh -c '"$1" restore >tag_drift.out 2>tag_drift.err' sh "$GIT_NEST"
assert_file_contains tag_drift.err "tag/revision mismatch for libs/foo"
test "$(git -C libs/foo rev-parse HEAD)" = "$head_before"

test_step "Run restore --force after reviewing drift" "--force should downgrade only the tag-drift check to a warning."
run_ok "restore proceeded after explicit force" -- sh -c '"$1" restore --force >tag_force.out 2>tag_force.err' sh "$GIT_NEST"
assert_file_contains tag_force.err "--force is proceeding"
test "$recorded" != "$(git -C "$seed" rev-parse HEAD)"
describe_result "restore protected the pinned tag by default and proceeded only after --force."
