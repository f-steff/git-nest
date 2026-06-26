#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin git_invocation

work=$(test_workspace git_invocation)
outer="$work/outer"

# This test validates Git external-command discovery, so it runs through git stack.
mkdir -p "$outer"
cd "$outer"

# Put the local bin directory on PATH just as a user installation would.
PATH="$REPO_ROOT/bin:$PATH"
export PATH

# Exercise version/help/init/status through Git's dispatch path.
test "$(git stack version)" = "git-stack 0.4.1"
git stack help >help.txt
assert_file_contains help.txt "status [--recursive] [--porcelain]"
assert_file_contains help.txt "Show stack and module state."
assert_file_contains help.txt "available [--recursive] [--porcelain]"
assert_file_contains help.txt "Check module remotes for newer target-branch commits without fetching."
assert_file_contains help.txt "refresh [--quiet]"
assert_file_contains help.txt "Refresh local manifest state without pushing."
git stack init >/dev/null
git stack status >status.txt
git stack log --max-count 1 >log.txt

test -f .stack
assert_file_contains status.txt "outer branch:"
