#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin init_add_start

work=$(test_workspace init_add_start)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

# Build one module remote and one outer workspace fixture.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

# Initialize, add the module, commit workspace metadata, and start a stack branch.
cd "$outer"
"$GIT_STACK" init >/dev/null
test ! -f .stack-rc
"$GIT_STACK" init --rc >/dev/null
test -f .stack-rc
"$GIT_STACK" add "$remote" libs/foo >/dev/null
git add .stack .gitignore .stack-rc
git commit -m "initial workspace" >/dev/null
"$GIT_STACK" start XX-123-short-description >/dev/null

# Verify init/add/start wrote the expected files, manifest state, and module branch.
test -f .stack
assert_file_contains .gitignore "libs/foo/"
assert_file_contains .stack '[module "libs/foo"]'
assert_file_contains .stack 'branch=XX-123-short-description'
test "$(git -C libs/foo branch --show-current)" = "XX-123-short-description"
