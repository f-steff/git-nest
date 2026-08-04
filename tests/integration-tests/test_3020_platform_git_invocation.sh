#!/bin/sh
# Test: git-nest works as a direct command and as a git subcommand, including help

set -eu
. "$(dirname "$0")/helper.sh"
test_begin platform_git_invocation

test_step "Exercise platform git invocation" "This test verifies the documented platform git invocation behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace platform_git_invocation)
outer="$work/outer"

# This test validates Git external-command discovery, so it runs through git nest.
mkdir -p "$outer"
cd "$outer"

# Put the local bin directory on PATH just as a user installation would.
PATH="$REPO_ROOT/bin:$PATH"
export PATH

# Exercise version/help/init/status through Git's dispatch path. The expected
# string is computed from the real entrypoint rather than hardcoded here: a
# hardcoded literal silently goes stale on every version bump (this test
# failed for exactly that reason -- it still expected 0.8.2 after the version
# moved to 0.8.3).
expected_version=$("$GIT_NEST_REAL" version)
test "$(git nest version)" = "$expected_version"
git nest help >help.txt
git nest help clone >help_clone.txt
git nest help snapshot >help_snapshot.txt
git nest help branch-mark >help_branch.txt
git nest help config >help_config.txt
git nest help hooks-install >help_hooks_install.txt
git nest help absorb >help_absorb.txt
assert_file_contains help.txt "  Nest setup"
assert_file_contains help.txt "  Workspace state"
assert_file_contains help.txt "  Branch bookmarks"
assert_file_contains help.txt "  Export and outer-repo conversion"
if LC_ALL=C grep "$(printf '\033')" help.txt >/dev/null 2>&1; then
    echo "redirected help should not contain ANSI color escapes" >&2
    exit 1
fi
GIT_NEST_COLOR=always git nest help >help_color.txt
LC_ALL=C grep "$(printf '\033')" help_color.txt >/dev/null 2>&1 || {
    echo "forced color help should contain ANSI color escapes" >&2
    exit 1
}
assert_file_contains help.txt "remove|rm <path> [--force] [--dry-run] [--json|--json-pretty]"
assert_file_contains help.txt "detach <path> [--dry-run] [--json|--json-pretty]"
assert_file_contains help.txt "move|mv <old-path> <new-path> [--force]"
assert_file_contains help.txt "clone <nest-repo-url> [target-dir]"
assert_file_contains help.txt "Run git clone for a nest repository and restore when it has a manifest."
assert_file_contains help.txt "It does not copy an existing local checkout."
assert_file_contains help.txt "status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
assert_file_contains help.txt "Show nest root and subproject state."
assert_file_contains help.txt "outdated [--recursive] [--porcelain | --json | --json-pretty]"
assert_file_contains help.txt "Check subproject remotes for newer target-branch commits without fetching."
assert_file_contains help.txt "diff [--since <ref>] [--stat] [--json | --json-pretty]"
assert_file_contains help.txt "Show subproject commits between manifest revisions and current checkouts."
assert_file_contains help.txt "config <get|set|list|unset> ..."
assert_file_contains help.txt "Read or update allowlisted manifest settings."
assert_file_contains help.txt "Only clone-mode is currently configurable; values are full, partial, or shallow."
assert_file_contains help.txt "clone-mode controls future restore clones, not the clone command."
assert_file_contains help.txt "config list shows explicitly set config values only."
assert_file_contains help.txt "snapshot [<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
assert_file_contains help.txt "Record clean, reproducible checked-out subproject commits in .gitnest."
assert_file_contains help.txt "No path snapshots all subprojects in the current nest."
assert_file_contains help.txt "At the nest root, . also means all subprojects."
assert_file_contains help.txt "Inside a managed subproject, . means that subproject only."
assert_file_contains help.txt "An explicit path may name a managed subproject or a path inside one."
assert_file_contains help.txt "restore [--recursive] [--prune] [--force] [--dry-run]"
assert_file_contains help.txt "Clone/fetch subprojects and restore the manifest state on disk."
assert_file_contains help.txt "freeze [--force] [--only <path>[,<path>...]] [--dry-run]"
assert_file_contains help.txt "hooks-install"
assert_file_contains help.txt "Install managed local Git hooks in all checked-out repositories in the current nest."
assert_file_contains help.txt "branch-mark [name]"
assert_file_contains help.txt "doctor [--json | --json-pretty] [--online | --offline] [--timeout <seconds>] [--exit-code]"
assert_file_contains help.txt "Report environment and workspace health without modifying files."
assert_file_contains help.txt "foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty]"
assert_file_contains help.txt "foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty]"
assert_file_contains help.txt "completion <bash|zsh|fish>"
assert_file_contains help.txt "Print a shell completion script to stdout."
assert_file_contains help.txt "export --output <path>"
assert_file_contains help.txt "Export a source snapshot with .gitnest and MANIFEST.lock."
assert_file_contains help.txt "dir output uses shell file copy; tar.gz requires system tar; zip requires python or python3."
assert_file_contains help_clone.txt "git-nest help: clone"
assert_file_contains help_clone.txt "This is a convenience wrapper around git clone plus git-nest restore."
assert_file_contains help_clone.txt "It does not copy an existing local checkout."
assert_file_contains help_clone.txt "Opposite: restore materializes subprojects after an ordinary git clone."
assert_file_contains help_snapshot.txt "git-nest help: snapshot"
assert_file_contains help_snapshot.txt "At the nest root, . also means all subprojects."
assert_file_contains help_snapshot.txt "Inside a managed subproject, . means that subproject only."
assert_file_contains help_snapshot.txt "git-nest snapshot libs/foo --dry-run"
assert_file_contains help_snapshot.txt "Opposite: restore materializes the recorded manifest state on disk."
assert_file_contains help_branch.txt "git-nest help: branch-mark"
assert_file_contains help_branch.txt "Branch bookmarks remember useful branch names for the current nest."
assert_file_contains help_branch.txt "branch-unmark removes one remembered branch name for the current repository."
assert_file_contains help_branch.txt "git-nest branch-list --verbose"
assert_file_contains help_config.txt "git-nest help: config"
assert_file_contains help_config.txt "Only clone-mode is currently configurable."
assert_file_contains help_config.txt "clone-mode values are full, partial, or shallow."
assert_file_contains help_config.txt "clone-mode controls future restore clones, not the clone command."
assert_file_contains help_config.txt "config list shows explicitly set config values only."
assert_file_contains help_config.txt "Unknown keys such as repo are rejected for get, set, and unset."
assert_file_contains help_config.txt "libs/foo    clone-mode=partial"
assert_file_contains help_config.txt "Error: unknown config key: repo"
assert_file_contains help_hooks_install.txt "git-nest help: hooks-install"
assert_file_contains help_hooks_install.txt "Install managed local Git hooks in all checked-out repositories in the current nest."
assert_file_contains help_hooks_install.txt "Opposite: hooks-uninstall removes the managed local hooks."
assert_file_contains help_absorb.txt "git-nest help: absorb"
assert_file_contains help_absorb.txt "Bring something already on disk into the nest as a managed subproject."
assert_file_contains help_absorb.txt "Auto-detects the source: outer-repo tracked files, a standalone nested repo, or a submodule."
if git nest help not-a-command >help_bad.out 2>help_bad.err; then
    echo "unknown help topic should fail" >&2
    exit 1
fi
assert_file_contains help_bad.err "unknown help topic: not-a-command"
git nest init >/dev/null
git nest status >status.txt
git nest log --max-count 1 >log.txt

test -f .gitnest
assert_file_contains status.txt "outer branch:"

describe_result "The platform git invocation behavior matched the expected command output and repository state."
