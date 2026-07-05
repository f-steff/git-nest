#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin git_invocation

work=$(test_workspace git_invocation)
outer="$work/outer"

# This test validates Git external-command discovery, so it runs through git lego.
mkdir -p "$outer"
cd "$outer"

# Put the local bin directory on PATH just as a user installation would.
PATH="$REPO_ROOT/bin:$PATH"
export PATH

# Exercise version/help/init/status through Git's dispatch path.
test "$(git lego version)" = "git-lego 0.7.0"
git lego help >help.txt
assert_file_contains help.txt "remove|rm <path> [--force] [--keep-files]"
assert_file_contains help.txt "mv <old-path> <new-path> [--force]"
assert_file_contains help.txt "clone <outer-repo-url> [target-dir]"
assert_file_contains help.txt "status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
assert_file_contains help.txt "Show project and subproject state."
assert_file_contains help.txt "outdated [--recursive] [--porcelain | --json | --json-pretty]"
assert_file_contains help.txt "Check subproject remotes for newer target-branch commits without fetching."
assert_file_contains help.txt "diff [--since <ref>] [--stat] [--json | --json-pretty]"
assert_file_contains help.txt "Show subproject commits between manifest revisions and current checkouts."
assert_file_contains help.txt "config <get|set|list|unset> ..."
assert_file_contains help.txt "Read or update allowlisted manifest settings."
assert_file_contains help.txt "snapshot [--recursive] [--quiet] [--no-fetch] [--base <subproject>=<ref>]"
assert_file_contains help.txt "Snapshot local manifest state without pushing."
assert_file_contains help.txt "freeze [--force] [--only <path>[,<path>...]] [--dry-run]"
assert_file_contains help.txt "foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty]"
assert_file_contains help.txt "foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty]"
assert_file_contains help.txt "completion <bash|zsh|fish>"
assert_file_contains help.txt "Print a shell completion script to stdout."
assert_file_contains help.txt "export --output <path>"
assert_file_contains help.txt "Export a source snapshot with .gitlego and MANIFEST.lock."
git lego init >/dev/null
git lego status >status.txt
git lego log --max-count 1 >log.txt

test -f .gitlego
assert_file_contains status.txt "outer branch:"
