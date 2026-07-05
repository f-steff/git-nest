#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin diff_config_foreach_filters

work=$(test_workspace diff_config_foreach_filters)
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
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote_one" libs/one >/dev/null
"$GIT_LEGO" add "$remote_two" libs/two >/dev/null
"$GIT_LEGO" add "$remote_three" libs/three >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

# Manifest-backed config writes clone mode only; existing checkouts are not converted.
set +e
"$GIT_LEGO" config get libs/one clone-mode >config_unset.out 2>config_unset.err
rc=$?
set -e
test "$rc" -eq 1

"$GIT_LEGO" config set libs/one clone-mode partial >config_set.out 2>config_set.err
assert_file_contains config_set.err "existing checkouts are not converted"
assert_file_contains .gitlego "clone=partial"
test "$("$GIT_LEGO" config get libs/one clone-mode)" = "partial"
"$GIT_LEGO" config list >config_list.out
assert_file_contains config_list.out "libs/one	clone-mode=partial"
"$GIT_LEGO" config unset libs/one clone-mode
assert_file_not_contains .gitlego "clone=partial"

if "$GIT_LEGO" config set libs/one clone-mode shallow >config_bad_value.out 2>config_bad_value.err; then
    echo "invalid clone-mode should fail" >&2
    exit 1
fi
assert_file_contains config_bad_value.err "clone-mode must be full or partial"
if "$GIT_LEGO" config get libs/one unknown-key >config_bad_key.out 2>config_bad_key.err; then
    echo "unknown config key should fail" >&2
    exit 1
fi
assert_file_contains config_bad_key.err "unknown config key"

# Diff reports commits that are in a subproject checkout but not in the manifest revision.
printf 'local feature\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "local feature for diff" >/dev/null

set +e
"$GIT_LEGO" diff >diff.out 2>diff.err
rc=$?
set -e
test "$rc" -eq 1
assert_file_contains diff.out "libs/one:"
assert_file_contains diff.out "local feature for diff"

set +e
"$GIT_LEGO" diff --stat >diff_stat.out 2>diff_stat.err
rc=$?
set -e
test "$rc" -eq 1
assert_file_contains diff_stat.out "local feature for diff"
assert_file_contains diff_stat.out "file.txt"

set +e
"$GIT_LEGO" diff --json >diff.json 2>diff_json.err
rc=$?
set -e
test "$rc" -eq 1
assert_file_contains diff.json '"command":"diff"'
assert_file_contains diff.json "local feature for diff"

"$GIT_LEGO" freeze --force --only libs/one >/dev/null
git add .gitlego
git commit -m "freeze one" >/dev/null

"$GIT_LEGO" diff >diff_clean.out
assert_file_contains diff_clean.out "No subproject commit differences"

set +e
"$GIT_LEGO" diff --since HEAD~1 >diff_since.out 2>diff_since.err
rc=$?
set -e
test "$rc" -eq 1
assert_file_contains diff_since.out "local feature for diff"

if "$GIT_LEGO" diff --since does-not-exist >diff_missing.out 2>diff_missing.err; then
    echo "diff --since missing ref should fail" >&2
    exit 1
fi
assert_file_contains diff_missing.err "cannot read .gitlego at does-not-exist"

# Filtered foreach commands select dirty and clean subprojects.
printf 'dirty work\n' >>libs/two/file.txt

"$GIT_LEGO" foreach-modified --porcelain >foreach_modified.out
assert_file_contains foreach_modified.out "F	libs/two	modified"
assert_file_not_contains foreach_modified.out "libs/one"
assert_file_not_contains foreach_modified.out "libs/three"

"$GIT_LEGO" foreach-clean --porcelain >foreach_clean.out
assert_file_contains foreach_clean.out "F	libs/one	clean"
assert_file_contains foreach_clean.out "F	libs/three	clean"
assert_file_not_contains foreach_clean.out "libs/two"

"$GIT_LEGO" foreach-modified --json >foreach_modified.json
assert_file_contains foreach_modified.json '"command":"foreach-modified"'
assert_file_contains foreach_modified.json '"path":"libs/two"'

"$GIT_LEGO" foreach-modified -- sh -c 'printf "%s\n" "$GIT_LEGO_SUBPROJECT_PATH" >>"$GIT_LEGO_ROOT/modified_command.out"'
assert_file_contains modified_command.out "libs/two"

set +e
"$GIT_LEGO" foreach-clean --continue-on-error -- sh -c '
    printf "%s\n" "$GIT_LEGO_SUBPROJECT_PATH" >>"$GIT_LEGO_ROOT/clean_continue.out"
    [ "$GIT_LEGO_SUBPROJECT_PATH" = "libs/one" ] && exit 9
    exit 0
' >/dev/null 2>&1
rc=$?
set -e
test "$rc" -eq 9
assert_file_contains clean_continue.out "libs/one"
assert_file_contains clean_continue.out "libs/three"
