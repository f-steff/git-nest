#!/bin/sh
# Test: git-nest interactive -- line-based menus, context transitions,
# scripted input (--ii-test/--ii-skip), and directory navigation.
#
# Menu entry numbers are NOT hardcoded: each step probes the menu in the
# current folder first (a --ii-test q session), extracts the number of
# the labels it needs from the rendered transcript, and feeds those
# numbers back in. Renumbering the menu table never breaks this test.
# (The labels are used as literal sed BRE text, so keep them free of
# regex metacharacters; the picker rows for live data stay positional.)

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_interactive

# Print the menu number for a label from a captured menu transcript.
ii_menu_number() {
    file=$1
    label=$2
    sed -n "s|^ *\([0-9][0-9]*\)\. $label .*|\1|p" "$file" | sed -n '1p'
}

work=$(test_workspace command_interactive)
# make_bare_remote reassigns the global `work` variable, so keep the
# workspace root in its own variable for the later steps.
work_root=$work
mkdir -p "$work"
cd "$work"

test_step "Virgin folder offers git init and runs it" "With no Git repository anywhere up the tree, the menu must offer the real git init, and choosing it must execute git init in a sub-shell with the cwd>command echo."
mkdir -p virgin
cd "$work/virgin"
run_capture "menu probe in a virgin folder" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
git_init_num=$(ii_menu_number probe.out "git init")
[ -n "$git_init_num" ] || {
    printf 'UNEXPECTED RESULT: virgin menu must offer the real git init\n' >&2
    exit 1
}
run_capture "interactive in a virgin folder" virgin.out virgin.err -- "$GIT_NEST" interactive --ii-test "$git_init_num" q
assert_file_contains virgin.out ">git-nest version"
assert_file_contains virgin.out "git-nest 0.8.26"
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

test_step "A Git repo without a nest offers git-nest init" "After git init, the same folder must now offer git-nest init, and choosing it creates the .gitnest manifest."
run_capture "menu probe in a git-only folder" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
init_num=$(ii_menu_number probe.out "git-nest init")
[ -n "$init_num" ] || {
    printf 'UNEXPECTED RESULT: git-only menu must offer git-nest init\n' >&2
    exit 1
}
run_capture "interactive in a git-only folder" gitonly.out gitonly.err -- "$GIT_NEST" interactive --ii-test "$init_num" q
assert_file_contains gitonly.out ">git-nest init"
assert_file_contains gitonly.out "Initialized git-nest workspace"
assert_file_not_contains gitonly.out ">git init"
[ -f .gitnest ] || {
    printf 'UNEXPECTED RESULT: git-nest init was not executed\n' >&2
    exit 1
}

test_step "Inside a nest the full menu appears with jump nest last" "The nest menu must group the whole command surface, and jump nest must be the highest-numbered entry. Number alignment itself is covered by the unit suite."
run_capture "menu probe in a nest" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
status_num=$(ii_menu_number probe.out "status")
jump_num=$(ii_menu_number probe.out "jump nest")
[ -n "$status_num" ] || {
    printf 'UNEXPECTED RESULT: nest menu must offer status\n' >&2
    exit 1
}
[ -n "$jump_num" ] || {
    printf 'UNEXPECTED RESULT: nest menu must offer jump nest\n' >&2
    exit 1
}
last_num=$(grep -E '^ *[0-9][0-9]*\. ' probe.out | sed 's/^ *\([0-9][0-9]*\)\..*/\1/' | sort -n | sed -n '$p')
[ "$jump_num" = "$last_num" ] || {
    printf 'UNEXPECTED RESULT: jump nest must be the last numbered entry (got %s, last %s)\n' "$jump_num" "$last_num" >&2
    exit 1
}
run_capture "interactive in a nest" nest.out nest.err -- "$GIT_NEST" interactive --ii-test "$status_num" q
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
run_capture "menu probe for skip step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
tidy_num=$(ii_menu_number probe.out "tidy")
clone_num=$(ii_menu_number probe.out "clone")
status_num=$(ii_menu_number probe.out "status")
run_capture "scripted input with skip" skip.out skip.err -- "$GIT_NEST" interactive --ii-test "$tidy_num" "$clone_num" "$status_num" q --ii-skip 2
assert_file_contains skip.out ">git-nest status"
assert_file_not_contains skip.out ">git-nest tidy"
assert_file_not_contains skip.out ">git-nest clone"

test_step "Directory navigation changes the cwd one layer at a time" "The change directory entry lists the parent as entry 0, then subdirectories; choosing one enters it, b returns to the main menu, and the next command echoes the new cwd."
mkdir -p "$work/virgin/sub"
cd "$work/virgin"
run_capture "menu probe for directory step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
cd_num=$(ii_menu_number probe.out "change directory")
version_num=$(ii_menu_number probe.out "version")
run_capture "directory navigation" cd.out cd.err -- "$GIT_NEST" interactive --ii-test "$cd_num" 2 b "$version_num" q
grep -E '^  0\. \.\. ' cd.out >/dev/null || {
    printf 'UNEXPECTED RESULT: directory picker must offer the parent as entry 0\n' >&2
    exit 1
}
grep -E '^  2\. sub/ ' cd.out >/dev/null || {
    printf 'UNEXPECTED RESULT: directory picker must list subdirectories after the parent\n' >&2
    exit 1
}
assert_file_contains cd.out "virgin/sub>git-nest version"

test_step "The browser offers nest-root and start-cwd anchors" "When the browser is entered from a folder inside the nest, the first render must offer the nest root and the folder the session started in as jump entries."
mkdir -p "$work/virgin/sub2"
cd "$work/virgin/sub2"
run_capture "menu probe for anchor step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
cd_num=$(ii_menu_number probe.out "change directory")
version_num=$(ii_menu_number probe.out "version")
run_capture "anchor jump to the nest root" anchors.out anchors.err -- "$GIT_NEST" interactive --ii-test "$cd_num" 1 b "$version_num" q
grep -E '^  1\. nest root  \(' anchors.out >/dev/null || {
    printf 'UNEXPECTED RESULT: browser must offer the nest root anchor first\n' >&2
    exit 1
}
grep -E '^  2\. start cwd  \(' anchors.out >/dev/null || {
    printf 'UNEXPECTED RESULT: browser must offer the start cwd anchor\n' >&2
    exit 1
}
assert_file_contains anchors.out "virgin>git-nest version"

test_step "Exhausted scripted input exits gracefully" "When the --ii-test token queue runs out, the session must end with exit 0 instead of waiting on a terminal."
mkdir -p "$work/exhaust"
cd "$work/exhaust"
"$GIT_NEST" init >/dev/null
run_capture "menu probe for exhausted step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
status_num=$(ii_menu_number probe.out "status")
run_capture "exhausted tokens" exhaust.out exhaust.err -- "$GIT_NEST" interactive --ii-test "$status_num"
assert_file_contains exhaust.out ">git-nest status"

test_step "Text-prompt commands accept the next token as arguments" "A command that takes arguments reads the following token as free text and echoes the full command line."
mkdir -p "$work/text"
cd "$work/text"
"$GIT_NEST" init >/dev/null
run_capture "menu probe for text step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
unmark_num=$(ii_menu_number probe.out "branch-unmark")
run_capture "text prompt command" text.out text.err -- "$GIT_NEST" interactive --ii-test "$unmark_num" missing-name q
assert_file_contains text.out "Enter arguments for branch-unmark (empty cancels): missing-name"
assert_file_contains text.out ">git-nest branch-unmark missing-name"

test_step "Bring-in flow shows survey findings and absorbs a detected repo" "The bring-in flow must run survey first, list the detected targets with their kinds, absorb a picked one through the right form, and re-render with the target gone."
mkdir -p "$work/flows"
cd "$work/flows"
"$GIT_NEST" init >/dev/null
# make_bare_remote reassigns the test's global `work` variable, so keep
# the flows dir in its own variable and use absolute paths throughout.
# The seed checkout lives OUTSIDE the flows nest, or survey would list
# it as a second unmanaged repo and the picker would never empty.
flows_dir="$work/flows"
make_bare_remote "$flows_dir/remotes/bar.git" "$work/flows-seed"
git clone -q "$flows_dir/remotes/bar.git" bar
run_capture "menu probe for bring-in step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
bringin_num=$(ii_menu_number probe.out "bring in (absorb)")
[ -n "$bringin_num" ] || {
    printf 'UNEXPECTED RESULT: nest menu must offer the bring-in flow\n' >&2
    exit 1
}
run_capture "bring-in flow" flowin.out flowin.err -- "$GIT_NEST" interactive --ii-test "$bringin_num" 1 q
assert_file_contains flowin.out ">git-nest survey"
assert_file_contains flowin.out "bar - nested-repo"
assert_file_contains flowin.out ">git-nest absorb bar"
assert_file_contains flowin.out "No unmanaged repositories or submodules detected."
grep -q 'subproject "bar"' .gitnest || {
    printf 'UNEXPECTED RESULT: bring-in flow did not absorb the nested repo\n' >&2
    exit 1
}

test_step "Take-out flow shows the tree and detaches a picked subproject" "The take-out flow must run tree --all first, let the user pick a managed subproject, choose a verb, confirm, and run the command."
run_capture "menu probe for take-out step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
takeout_num=$(ii_menu_number probe.out "take out (inline/detach/remove)")
[ -n "$takeout_num" ] || {
    printf 'UNEXPECTED RESULT: nest menu must offer the take-out flow\n' >&2
    exit 1
}
run_capture "take-out flow" flowout.out flowout.err -- "$GIT_NEST" interactive --ii-test "$takeout_num" 1 d y q
assert_file_contains flowout.out ">git-nest tree --all"
assert_file_contains flowout.out "Take out bar: inline (i), detach (d), or remove (r)? d"
assert_file_contains flowout.out "Run git-nest detach bar? [y/N]: y"
assert_file_contains flowout.out ">git-nest detach bar"

test_step "move browses the nest for the destination and adds a name" "move must pick the source subproject, browse the nest (select mode, capped at the nest root), and let the user select a folder plus a new name, then run move with the composed path."
move_dir="$work_root/move-nest"
mkdir -p "$move_dir"
cd "$move_dir"
"$GIT_NEST" init >/dev/null
# make_bare_remote reassigns the test's global `work` variable, so the
# move dir is kept in its own variable and paths stay absolute.
make_bare_remote "$move_dir/remotes/bar.git" "$work_root/move-seed"
git clone -q "$move_dir/remotes/bar.git" libs/bar
"$GIT_NEST" absorb libs/bar >/dev/null
run_capture "menu probe for move step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
move_num=$(ii_menu_number probe.out "move")
[ -n "$move_num" ] || {
    printf 'UNEXPECTED RESULT: nest menu must offer move\n' >&2
    exit 1
}
run_capture "browse-move" move.out move.err -- "$GIT_NEST" interactive --ii-test "$move_num" 1 2 n tools q
assert_file_contains move.out ">git-nest move libs/bar libs/tools"
grep -q 'subproject "libs/tools"' .gitnest || {
    printf 'UNEXPECTED RESULT: browse-move did not record the new subproject path\n' >&2
    exit 1
}

test_step "jump nest finds nested nests and returns to visited ones" "jump nest must list a managed subproject that is itself a nest, jump into it, and on the next jump offer the previous nest from the session history."
jump_dir="$work_root/jump"
mkdir -p "$jump_dir"
cd "$jump_dir"
"$GIT_NEST" init >/dev/null
make_bare_remote "$jump_dir/remotes/bar.git" "$work_root/jump-seed"
git clone -q "$jump_dir/remotes/bar.git" libs/nested-app
# Make the subproject a nest itself (composite), then absorb it.
cd libs/nested-app
"$GIT_NEST" init --sure >/dev/null
cd "$jump_dir"
"$GIT_NEST" absorb libs/nested-app >/dev/null
run_capture "menu probe for jump step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
jump_num=$(ii_menu_number probe.out "jump nest")
[ -n "$jump_num" ] || {
    printf 'UNEXPECTED RESULT: nest menu must offer jump nest\n' >&2
    exit 1
}
run_capture "jump nest flow" jump.out jump.err -- "$GIT_NEST" interactive --ii-test "$jump_num" 1 "$jump_num" 1 q
assert_file_contains jump.out "composite nest"
assert_file_contains jump.out "previously visited"
[ "$(grep -c 'Now in nest:' jump.out)" -eq 2 ] || {
    printf 'UNEXPECTED RESULT: jump nest must move the session twice (in and back)\n' >&2
    exit 1
}
grep 'Now in nest:' jump.out | grep -q 'nested-app' || {
    printf 'UNEXPECTED RESULT: first jump must land in the nested nest\n' >&2
    exit 1
}

describe_result "git-nest interactive drives the full command surface from line-based menus: virgin->git init->git-nest init->nest transitions, invalid/back handling, --ii-skip fast-forward, one-layer directory navigation with anchors, graceful EOF, the bring-in/take-out membership flows, browse-move, and jump nest. Entry numbers are probed from the rendered menu, never hardcoded."
