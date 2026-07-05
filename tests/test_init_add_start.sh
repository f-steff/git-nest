#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin init_add_start

work=$(test_workspace init_add_start)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

# Build one subproject remote and one outer workspace fixture.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

# Initialize, add the subproject, commit workspace metadata, and start a project branch.
cd "$outer"
"$GIT_LEGO" init >/dev/null
test ! -f .gitlego-rc
"$GIT_LEGO" init --rc >/dev/null
test -f .gitlego-rc
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes .gitattributes .gitlego-rc
git commit -m "initial workspace" >/dev/null
"$GIT_LEGO" start XX-123-short-description >/dev/null

# Verify init/add/start wrote the expected files, manifest state, and subproject branch.
test -f .gitlego
assert_file_contains .gitignore "libs/foo/"
assert_file_contains .gitlego '[subproject "libs/foo"]'
assert_file_contains .gitlego 'branch=XX-123-short-description'
test "$(git -C libs/foo branch --show-current)" = "XX-123-short-description"
