#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_finalize_auto_token_match

root=$(test_workspace command_finalize_auto_token_match)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
test_step "Create a pending subproject with ticket AB-1" "finalize auto-resolution uses the project ticket to find the landed commit."
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
run_ok "project branch started for AB-1" -- "$GIT_LEGO" start AB-1-token-test
printf 'ab1\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "subproject change" >/dev/null
run_ok "subproject work uploaded and recorded as pending" -- "$GIT_LEGO" upload

test_step "Add similarly named noise commits on the target branch" "auto-finalize must match ticket tokens, not substrings such as ZAB-12 or AB-12."
git -C libs/foo checkout main >/dev/null
printf 'noise\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "ZAB-12 unrelated" >/dev/null
printf 'noise2\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "AB-12 unrelated" >/dev/null
printf 'landed\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "foo AB-1" >/dev/null
git -C libs/foo push origin main >/dev/null
git -C libs/foo checkout AB-1-token-test >/dev/null

test_step "Finalize without an explicit selector" "the command should find exactly the AB-1 landed commit and clear pending state."
run_ok "pending state finalized through token-bound auto-detection" -- "$GIT_LEGO" finalize libs/foo
if grep -F 'pending_branch=' .gitlego >/dev/null; then
    echo "token-bound auto-finalize did not finalize pending state" >&2
    exit 1
fi
describe_result "finalize ignored substring matches and converted libs/foo from pending to finalized."
