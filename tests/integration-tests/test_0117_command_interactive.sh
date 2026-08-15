#!/bin/sh
# Test: git-nest interactive -- line-based menus, context transitions,
# scripted input (--ii-test/--ii-skip), and directory navigation.

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_interactive

work=$(test_workspace command_interactive)
mkdir -p "$work"
cd "$work"

test_step "Virgin folder offers git init and runs it" "With no Git repository anywhere up the tree, the menu must offer the real git init as entry 1, and choosing it must execute git init in a sub-shell with the cwd>command echo."
mkdir -p virgin
cd "$work/virgin"
run_capture "interactive in a virgin folder" virgin.out virgin.err -- "$GIT_NEST" interactive --ii-test 1 q
assert_file_contains virgin.out ">git-nest version"
assert_file_contains virgin.out "git-nest 0.8.26"
grep -E '^  1\. git init ' virgin.out >/dev/null || {
    printf 'UNEXPECTED RESULT: virgin menu must offer the real git init first\n' >&2
    exit 1
}
grep -E '^  b\. back ' virgin.out >/dev/null || {
    printf 'UNEXPECTED RESULT: menu must show the back footer\n' >&2
    exit 1
}
grep -E '^  q\. quit ' virgin.out >/dev/null || {
    printf 'UNEXPECTED RESULT: menu must show the quit footer\n' >&2
    exit 1
}
assert_file_contains virgin.out ">git init"
assert_file_contains virgin.out "Initialized empty Git repository"
[ -d .git ] || {
    printf 'UNEXPECTED RESULT: git init was not executed in the virgin folder\n' >&2
    exit 1
}

test_step "A Git repo without a nest offers git-nest init" "After git init, the same folder must now offer git-nest init as entry 1, and choosing it creates the .gitnest manifest."
run_capture "interactive in a git-only folder" gitonly.out gitonly.err -- "$GIT_NEST" interactive --ii-test 1 14 q
grep -E '^  1\. git-nest init ' gitonly.out >/dev/null || {
    printf 'UNEXPECTED RESULT: git-only menu must offer git-nest init first\n' >&2
    exit 1
}
assert_file_contains gitonly.out ">git-nest init"
assert_file_contains gitonly.out "Initialized git-nest workspace"
assert_file_not_contains gitonly.out ">git init"
[ -f .gitnest ] || {
    printf 'UNEXPECTED RESULT: git-nest init was not executed\n' >&2
    exit 1
}

test_step "Inside a nest the full menu appears with right-aligned numbers" "The nest menu must group the whole command surface and keep two-digit numbers aligned under one-digit numbers."
run_capture "interactive in a nest" nest.out nest.err -- "$GIT_NEST" interactive --ii-test 14 q
grep -E '^  1\. tidy ' nest.out >/dev/null || {
    printf 'UNEXPECTED RESULT: nest menu must start with tidy\n' >&2
    exit 1
}
grep -E '^ 10\. pull ' nest.out >/dev/null || {
    printf 'UNEXPECTED RESULT: two-digit numbers must right-align under one-digit numbers\n' >&2
    exit 1
}
grep -E '^ 37\. change directory ' nest.out >/dev/null || {
    printf 'UNEXPECTED RESULT: change directory must be the last numbered entry\n' >&2
    exit 1
}
assert_file_contains nest.out ">git-nest status"
grep -E '^outer branch: ' nest.out >/dev/null || {
    printf 'UNEXPECTED RESULT: status must print the outer branch line\n' >&2
    exit 1
}
assert_file_contains nest.out "subprojects:"

test_step "Invalid input and back at the top level" "A non-number choice must print Unknown choice and re-render; b at the top-level menu must report that there is no previous menu."
run_capture "invalid input and top-level back" invalid.out invalid.err -- "$GIT_NEST" interactive --ii-test x b q
assert_file_contains invalid.out "Unknown choice: x"
assert_file_contains invalid.out "You are already at the top-level menu."

test_step "--ii-skip drops leading tokens" "Tokens before --ii-skip n are never executed; the session starts feeding at token n+1, which lets a test fast-forward past setup a previous run already applied."
run_capture "scripted input with skip" skip.out skip.err -- "$GIT_NEST" interactive --ii-test 1 2 14 q --ii-skip 2
assert_file_contains skip.out ">git-nest status"
assert_file_not_contains skip.out ">git-nest tidy"
assert_file_not_contains skip.out ">git-nest clone"

test_step "Directory navigation changes the cwd one layer at a time" "The change directory entry lists subdirectories; choosing one enters it, b returns to the main menu, and the next command echoes the new cwd."
mkdir -p "$work/virgin/sub"
cd "$work/virgin"
run_capture "directory navigation" cd.out cd.err -- "$GIT_NEST" interactive --ii-test 37 2 b 36 q
grep -E '^  1\. \.\. ' cd.out >/dev/null || {
    printf 'UNEXPECTED RESULT: directory picker must offer the parent first\n' >&2
    exit 1
}
grep -E '^  2\. sub ' cd.out >/dev/null || {
    printf 'UNEXPECTED RESULT: directory picker must list subdirectories\n' >&2
    exit 1
}
assert_file_contains cd.out "$work/virgin/sub>git-nest version"

test_step "Exhausted scripted input exits gracefully" "When the --ii-test token queue runs out, the session must end with exit 0 instead of waiting on a terminal."
mkdir -p "$work/exhaust"
cd "$work/exhaust"
"$GIT_NEST" init >/dev/null
run_capture "exhausted tokens" exhaust.out exhaust.err -- "$GIT_NEST" interactive --ii-test 14
assert_file_contains exhaust.out ">git-nest status"

test_step "Text-prompt commands accept the next token as arguments" "A command that takes arguments reads the following token as free text and echoes the full command line."
mkdir -p "$work/text"
cd "$work/text"
"$GIT_NEST" init >/dev/null
run_capture "text prompt command" text.out text.err -- "$GIT_NEST" interactive --ii-test 24 missing-name q
assert_file_contains text.out "Enter arguments for branch-unmark (empty cancels): missing-name"
assert_file_contains text.out ">git-nest branch-unmark missing-name"

describe_result "git-nest interactive drives the full command surface from line-based menus: virgin->git init->git-nest init->nest transitions, right-aligned numbering, invalid/back handling, --ii-skip fast-forward, one-layer directory navigation, and graceful EOF."
