#!/bin/sh
# Test: foreach-modified and foreach-clean select and operate on the right subprojects

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_foreach_filters

work=$(test_workspace command_foreach_filters)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
remote_three="$work/remotes/three.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
seed_three="$work/seed/three"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
"$GIT_NEST" add "$remote_three" libs/three >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

test_step "Dirty one subproject" "foreach-modified and foreach-clean should partition checked-out subprojects by working-tree state."
printf 'dirty work\n' >>libs/two/file.txt

run_capture "dirty subproject listed in porcelain output" foreach_modified.out foreach_modified.err -- "$GIT_NEST" foreach-modified --porcelain
assert_file_contains foreach_modified.out "F	libs/two	modified"
assert_file_not_contains foreach_modified.out "libs/one"
assert_file_not_contains foreach_modified.out "libs/three"
run_capture "clean subprojects listed in porcelain output" foreach_clean.out foreach_clean.err -- "$GIT_NEST" foreach-clean --porcelain
assert_file_contains foreach_clean.out "F	libs/one	clean"
assert_file_contains foreach_clean.out "F	libs/three	clean"
assert_file_not_contains foreach_clean.out "libs/two"
run_capture "dirty subproject listed in JSON output" foreach_modified.json foreach_modified_json.err -- "$GIT_NEST" foreach-modified --json
assert_file_contains foreach_modified.json '"command":"foreach-modified"'
assert_file_contains foreach_modified.json '"path":"libs/two"'

test_step "Run commands through filtered foreach modes" "the selected subproject context should be exposed through environment variables."
run_ok "foreach-modified ran only in the dirty subproject" -- "$GIT_NEST" foreach-modified -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/modified_command.out"'
assert_file_contains modified_command.out "libs/two"
run_fail "foreach-clean continued through all clean subprojects and returned the failing status" 9 -- sh -c '"$1" foreach-clean --continue-on-error -- sh -c '"'"'
    printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/clean_continue.out"
    [ "$GIT_NEST_SUBPROJECT_PATH" = "libs/one" ] && exit 9
    exit 0
'"'"' >/dev/null 2>&1' sh "$GIT_NEST"
assert_file_contains clean_continue.out "libs/one"
assert_file_contains clean_continue.out "libs/three"
describe_result "foreach-modified and foreach-clean selected the expected repositories and propagated command status."

test_step "Foreach -- separator is optional" "Both with and without -- should produce the same result."
run_ok "foreach without -- runs command" -- "$GIT_NEST" foreach sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH"'
run_ok "foreach with -- runs command" -- "$GIT_NEST" foreach -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH"'
run_ok "foreach-modified without -- runs command in dirty subproject" -- "$GIT_NEST" foreach-modified sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH"'
run_ok "foreach-clean without -- runs command in clean subprojects" -- "$GIT_NEST" foreach-clean sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH"'
describe_result "All foreach variants accepted commands without -- separator."

test_step "foreach --include-root-first runs the command on the nest root before subprojects" "The root's GIT_NEST_SUBPROJECT_PATH should be '.' and it should appear before subproject entries."
rm -f foreach_root.out
"$GIT_NEST" foreach --include-root-first -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/foreach_root.out"'
head -1 foreach_root.out >first_line.out
assert_file_contains first_line.out "."
assert_file_contains foreach_root.out "libs/one"
assert_file_contains foreach_root.out "libs/two"
assert_file_contains foreach_root.out "libs/three"

test_step "foreach --include-root-last runs the command on the nest root after subprojects" "The root entry should be the last line."
rm -f foreach_root.out
"$GIT_NEST" foreach --include-root-last -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/foreach_root.out"'
tail -1 foreach_root.out >last_line.out
assert_file_contains last_line.out "."

test_step "foreach --only-nested runs only in subprojects that are themselves nests" "Create a nested nest, then verify --only-nested selects only it and --no-nested excludes it."
# Clone a remote and absorb it as a subproject, then turn it into a nested nest
remote_nested="$work/remotes/nested.git"
make_bare_remote "$remote_nested" "$work/seed/nested-seed"
git clone "$remote_nested" nested >/dev/null 2>&1
"$GIT_NEST" absorb nested >/dev/null
(
    cd nested
    "$GIT_NEST" init --sure >/dev/null
    "$GIT_NEST" add "$remote_one" nested-inner >/dev/null
    git add .gitnest .gitignore .gitattributes NEST_README.md
    git commit -qm "nested nest init"
)
rm -f foreach_nested.out
"$GIT_NEST" foreach --only-nested -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/foreach_nested.out"'
assert_file_contains foreach_nested.out "nested"
grep -c "nested" foreach_nested.out | grep -q "^1$"
for f in libs/one libs/two libs/three; do
    assert_file_not_contains foreach_nested.out "$f"
done

test_step "foreach --no-nested skips subprojects that are themselves nests" "Plain subprojects should still run, but the nested one should not appear."
rm -f foreach_nonested.out
"$GIT_NEST" foreach --no-nested -- sh -c 'printf "%s\n" "$GIT_NEST_SUBPROJECT_PATH" >>"$GIT_NEST_ROOT/foreach_nonested.out"'
assert_file_not_contains foreach_nonested.out "nested"
for f in libs/one libs/two libs/three; do
    assert_file_contains foreach_nonested.out "$f"
done
