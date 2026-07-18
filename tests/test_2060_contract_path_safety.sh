#!/bin/sh
# Test: path operations reject unsafe and backslash paths

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_path_safety

test_step "Exercise contract path safety" "This test verifies the documented contract path safety behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_path_safety)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

bad_path='libs\bar'
expected='Error: subproject paths must use forward slashes; got "libs\bar". Use "libs/bar".'

assert_bad_path() {
    label=$1
    shift
    set +e
    "$@" >"$label.out" 2>"$label.err"
    actual=$?
    set -e
    if [ "$actual" -eq 0 ]; then
        printf '%s should reject backslash path\n' "$label" >&2
        exit 1
    fi
    test "$actual" = 2
    assert_file_contains "$label.err" "$expected"
}

assert_bad_path add "$GIT_NEST" add "$remote" "$bad_path"
assert_bad_path remove "$GIT_NEST" remove "$bad_path" --force
assert_bad_path mv_old "$GIT_NEST" mv "$bad_path" libs/bar
assert_bad_path mv_new "$GIT_NEST" mv libs/foo "$bad_path"
assert_bad_path move "$GIT_NEST" move libs/foo "$bad_path"
assert_bad_path config "$GIT_NEST" config set "$bad_path" clone-mode full
assert_bad_path update "$GIT_NEST" update "$bad_path" --revision HEAD
assert_bad_path freeze "$GIT_NEST" freeze --only "$bad_path" --dry-run

mkdir -p plain
printf 'plain\n' >plain/file.txt
git add plain/file.txt
git commit -m "add plain directory" >/dev/null
assert_bad_path absorb "$GIT_NEST" absorb "$bad_path" "$remote" --dry-run
assert_bad_path inline "$GIT_NEST" inline "$bad_path" --dry-run
assert_bad_path detach "$GIT_NEST" detach "$bad_path" --dry-run

assert_exit_code 3 "$GIT_NEST" add "$remote" .git >/dev/null 2>&1
assert_exit_code 3 "$GIT_NEST" add "$remote" ../outside >/dev/null 2>&1

test_step "Reject unsafe subproject paths embedded in the manifest" "A crafted .gitnest whose subproject path escapes the nest (via ..) must be refused by schema validation before any command clones, checks out, or removes it."
cp .gitnest .gitnest.bak
printf '\n[subproject "../escape"]\nrepo=%s\ntarget_branch=main\n' "$remote" >>.gitnest
if "$GIT_NEST" status >manifest_escape.out 2>manifest_escape.err; then
    printf 'UNEXPECTED RESULT: a manifest with a ../ subproject path should be rejected\n' >&2
    exit 1
fi
assert_file_contains manifest_escape.err "unsafe subproject path"
# An absolute manifest path is likewise refused.
cp .gitnest.bak .gitnest
printf '\n[subproject "/etc/evil"]\nrepo=%s\ntarget_branch=main\n' "$remote" >>.gitnest
if "$GIT_NEST" verify >manifest_abs.out 2>manifest_abs.err; then
    printf 'UNEXPECTED RESULT: a manifest with an absolute subproject path should be rejected\n' >&2
    exit 1
fi
assert_file_contains manifest_abs.err "unsafe subproject path"
mv .gitnest.bak .gitnest

test_step "Reject case-insensitive path collisions" "On case-insensitive filesystems two paths differing only by case share a directory, so add/move must refuse a case-variant of an existing subproject."
if "$GIT_NEST" add "$remote" libs/FOO >case_add.out 2>case_add.err; then
    printf 'UNEXPECTED RESULT: add should refuse a case-only-different path\n' >&2
    exit 1
fi
assert_file_contains case_add.err "collides with existing subproject libs/foo"
"$GIT_NEST" add "$remote" libs/bar >/dev/null
if "$GIT_NEST" move libs/bar libs/FOO >case_mv.out 2>case_mv.err; then
    printf 'UNEXPECTED RESULT: move should refuse a case-only-different target\n' >&2
    exit 1
fi
assert_file_contains case_mv.err "collides with existing subproject libs/foo"

describe_result "The contract path safety behavior matched the expected command output and repository state, including manifest-content path escapes and case-insensitive collisions."
