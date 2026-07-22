#!/bin/sh
# Test: subproject paths containing spaces work correctly across commands

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_paths_with_spaces

# A path containing a space is a completely ordinary, valid filesystem path
# (especially common on Windows) and must work everywhere git-nest reads or
# writes a subproject path: the manifest cache (which used to build shell
# variable names by lossily substituting characters, breaking on a literal
# space with "bad substitution"), the human-readable success/summary
# messages (which used to interpolate the raw path into a suggested shell
# command without quoting it, producing a suggestion that is unsafe to copy
# and paste), and the boundary guards added for absorb/add.
test_step "Exercise subproject paths containing spaces" "A space is an ordinary path character; every command that stores, reads, prints, or suggests a command for a subproject path must handle it correctly."

root=$(test_workspace contract_paths_with_spaces)
outer="$root/outer"
remote_foo="$root/remotes/my remote.git"
remote_bar="$root/remotes/bar.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/my remote"
make_bare_remote "$remote_bar" "$root/seed/bar"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "init nest" >/dev/null

# --- add: a space-containing path must clone, read HEAD, and write the
# manifest correctly (this used to fail inside manifest_get with "bad
# substitution" once the cache tried to read the freshly-written entry back) ---
test_step "add a subproject at a space-containing path" "The manifest cache builds a variable name per subproject; a literal space in the path used to break that variable name entirely."
run_ok "added subproject with a space in its path" -- "$GIT_NEST" add "file://$remote_foo" "libs/my project"
assert_file_contains .gitnest '[subproject "libs/my project"]'
assert_file_contains .gitignore 'libs/my project/'
test -d "libs/my project/.git"

# --- status/list/verify must all read the cache correctly for this path ---
test_step "status, list, and verify read the space-containing path correctly" "These commands read subproject metadata through the same manifest cache that add just wrote to."
run_capture "status reports the space-containing subproject" status.out status.err -- "$GIT_NEST" status
assert_file_contains status.out "libs/my project"
run_capture "list reports the space-containing subproject" list.out list.err -- "$GIT_NEST" list
assert_file_contains list.out "libs/my project"
run_ok "verify passes for the space-containing subproject" -- "$GIT_NEST" verify

# --- config set/list ---
test_step "config set and list handle the space-containing path" "config keys a subproject by its path; the path must round-trip through the same encoding."
run_ok "config set on the space-containing path" -- "$GIT_NEST" config set "libs/my project" clone-mode full
assert_file_contains .gitnest 'clone=full'
run_capture "config list includes the space-containing path" configlist.out configlist.err -- "$GIT_NEST" config list
assert_file_contains configlist.out "libs/my project"

# --- move: also regression-covers a real bug found alongside this work,
# where write_materialized_state's internal loop reused the caller's
# old_path/new_path variable names (unrelated to spaces, but found via this
# same testing pass), silently clearing the "Moved subproject X to Y"
# message's source path on every move, regardless of whether it had spaces ---
test_step "move renames a space-containing path and reports both paths correctly" "The success message must name both the source and destination path; a prior bug cleared the source path on every move."
run_capture "move reports both paths in its message" move.out move.err -- "$GIT_NEST" move "libs/my project" "libs/another one"
assert_file_contains move.out "Moved subproject libs/my project to libs/another one."
assert_file_contains .gitnest '[subproject "libs/another one"]'
assert_file_not_contains .gitnest '[subproject "libs/my project"]'
test -d "libs/another one/.git"
test ! -e "libs/my project"

# --- survey: an unmanaged nested repo with a space in its path, and the
# suggested absorb command must be shell-quoted so it is safe to copy/paste.
# Deliberately not under vendor/ (or another name in SURVEY_DEFAULT_EXCLUDES)
# since those are pruned by design and would never be reported. ---
test_step "survey reports a space-containing unmanaged repo with a quoted suggestion" "The suggested absorb command must be safe to copy and paste verbatim even when the path contains a space."
git clone -q "file://$remote_bar" "external/other project" >/dev/null 2>&1
run_capture "survey finds the space-containing unmanaged repo" discover.out discover.err -- "$GIT_NEST" survey
assert_file_contains discover.out "external/other project"
assert_file_contains discover.out "run git-nest absorb 'external/other project' to manage it"

# --- absorb (existing nested-repo source) on that same space-containing path ---
test_step "absorb an existing nested repo at a space-containing path" "The nested-repo absorb source must also survive the space in the path."
run_ok "absorbed nested repo with a space in its path" -- "$GIT_NEST" absorb "external/other project"
assert_file_contains .gitnest '[subproject "external/other project"]'

# --- absorb --subrepo and --subtree with space-containing paths ---
test_step "absorb --subrepo and --subtree handle space-containing paths" "Both explicit conversion sources must also survive a space in the path."
mkdir -p "vendor/sub repo"
printf 'hi\n' >"vendor/sub repo/a.txt"
cat >"vendor/sub repo/.gitrepo" <<EOF
[subrepo]
	remote = file://$remote_bar
	branch = main
	commit = 0000000000000000000000000000000000000000
EOF
git add "vendor/sub repo"
git commit -m "add vendor/sub repo" >/dev/null
run_ok "absorbed subrepo with a space in its path" -- "$GIT_NEST" absorb --subrepo "vendor/sub repo"
assert_file_contains .gitnest '[subproject "vendor/sub repo"]'

mkdir -p "vendor/sub tree"
printf 'hi\n' >"vendor/sub tree/b.txt"
git add "vendor/sub tree"
git commit -m "add vendor/sub tree" >/dev/null
run_ok "absorbed subtree with a space in its path" -- "$GIT_NEST" absorb --subtree "vendor/sub tree" "file://$remote_bar"
assert_file_contains .gitnest '[subproject "vendor/sub tree"]'

# --- boundary guards must still work with a space in either path ---
test_step "boundary guards refuse paths inside or containing a space-containing subproject" "The boundary fix must recognize a space-containing subproject as a boundary in both directions."
run_fail "path inside a space-containing subproject refused" any -- sh -c '"$1" add "$2" "vendor/sub repo/deeper" >inside.out 2>inside.err' sh "$GIT_NEST" "file://$remote_bar"
assert_file_contains inside.err "is inside managed subproject vendor/sub repo"
run_fail "path containing a space-containing subproject refused" any -- sh -c '"$1" absorb vendor "$2" --dry-run >contains.out 2>contains.err' sh "$GIT_NEST" "file://$remote_bar"
assert_file_contains contains.err "contains managed subproject vendor/sub repo"

# --- pull: a subproject with no upstream tracking must report a quoted
# fix-it suggestion for a space-containing path. vendor/sub repo and
# vendor/sub tree were created via absorb (git init + remote add, no branch
# tracking set up), so they land in the no-upstream-tracking category; a
# cloned path like libs/another one or external/other project already has
# tracking and is simply reported as up to date. ---
test_step "pull reports a quoted fix-it suggestion for a space-containing path" "pull's summary embeds the path in a suggested git command; it must be quoted so copy-paste is safe."
run_capture "pull reports the space-containing path with a quoted suggestion" pull.out pull.err -- "$GIT_NEST" pull
assert_file_contains pull.out "external/other project: already up to date."
assert_file_contains pull.out "vendor/sub repo (run: git -C 'vendor/sub repo' branch --set-upstream-to=origin/main)"

# --- remove: delete a space-containing subproject cleanly ---
test_step "remove deletes a space-containing subproject cleanly" "remove must untrack and delete the checkout regardless of the space in its path."
run_ok "removed the space-containing subproject" -- "$GIT_NEST" remove "vendor/sub tree" --force
assert_file_not_contains .gitnest '[subproject "vendor/sub tree"]'
test ! -e "vendor/sub tree"

# --- export: both a space-containing subproject path and a space-containing
# output path must work ---
test_step "export handles a space-containing subproject and output path" "export copies each subproject's tracked files into the staged archive/directory by path."
run_ok "exported to a space-containing directory" -- "$GIT_NEST" export --output "$root/export dir" --format dir
test -d "$root/export dir/libs/another one"
test -d "$root/export dir/external/other project"

describe_result "Subproject paths containing spaces were correctly stored, read, converted, guarded, and reported (with safely quoted suggestions) across add, absorb (all sources), move, config, survey, pull, remove, and export."
