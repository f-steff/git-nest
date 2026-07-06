#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_init_add_start

test_step "Exercise workflow init add start" "This test verifies the documented workflow init add start behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace workflow_init_add_start)
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

describe_result "The workflow init add start behavior matched the expected command output and repository state."
