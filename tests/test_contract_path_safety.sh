#!/bin/sh

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
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
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

assert_bad_path add "$GIT_LEGO" add "$remote" "$bad_path"
assert_bad_path remove "$GIT_LEGO" remove "$bad_path" --force
assert_bad_path mv_old "$GIT_LEGO" mv "$bad_path" libs/bar
assert_bad_path mv_new "$GIT_LEGO" mv libs/foo "$bad_path"
assert_bad_path config "$GIT_LEGO" config set "$bad_path" clone-mode full
assert_bad_path update "$GIT_LEGO" update "$bad_path" --revision HEAD
assert_bad_path finalize "$GIT_LEGO" finalize "$bad_path" --revision HEAD
assert_bad_path freeze "$GIT_LEGO" freeze --only "$bad_path" --dry-run

mkdir -p plain
printf 'plain\n' >plain/file.txt
git add plain/file.txt
git commit -m "add plain directory" >/dev/null
assert_bad_path extract "$GIT_LEGO" extract "$bad_path" "$remote" --dry-run
assert_bad_path absorb "$GIT_LEGO" absorb "$bad_path" --dry-run

assert_exit_code 3 "$GIT_LEGO" add "$remote" .git >/dev/null 2>&1
assert_exit_code 3 "$GIT_LEGO" add "$remote" ../outside >/dev/null 2>&1

describe_result "The contract path safety behavior matched the expected command output and repository state."
