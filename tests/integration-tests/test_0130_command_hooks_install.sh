#!/bin/sh
# Test: hooks-install writes the correct hook sets, refuses unmanaged hooks, and auto-installs on add

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_hooks_install

# Installation must write the right managed hook set in the right repositories,
# refuse to clobber unmanaged hooks (all-or-nothing), reject recursion, and
# auto-install into newly added subprojects when the nest already uses hooks.
test_step "Exercise hook installation" "hooks-install writes root and subproject hook sets, refuses unmanaged hooks before writing any, rejects --recursive, and add auto-installs hooks into a new subproject when the nest is already hooked."

root=$(test_workspace command_hooks_install)
remote_foo="$root/remotes/foo.git"
remote_bar="$root/remotes/bar.git"
outer="$root/outer"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_bar" "$root/seed/bar"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_foo" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

# --- All-or-nothing preflight: an unmanaged hook blocks the whole install ---
test_step "Refuse to overwrite unmanaged hooks" "If any target has an unmanaged hook, install must fail before writing any managed hook."
printf '#!/bin/sh\n' >.git/hooks/pre-push
run_fail "unmanaged hook blocks install" any -- sh -c '"$1" hooks-install >unmanaged.out 2>unmanaged.err' sh "$GIT_NEST"
assert_file_contains unmanaged.err "refusing to overwrite unmanaged hook"
# The preflight ran before writing, so the managed post-checkout was not created.
test ! -f .git/hooks/post-checkout
rm -f .git/hooks/pre-push

# --- Successful install writes the documented hook sets ---
test_step "Install the managed hook sets" "The nest root gets post-checkout, pre-commit, and pre-push; subprojects get post-checkout and pre-push only."
run_ok "hooks installed across the nest" -- "$GIT_NEST" hooks-install
for hook in post-checkout pre-commit pre-push; do
    test -f ".git/hooks/$hook"
    assert_file_contains ".git/hooks/$hook" "# git-nest managed hook"
done
for hook in post-checkout pre-push; do
    test -f "libs/foo/.git/hooks/$hook"
    assert_file_contains "libs/foo/.git/hooks/$hook" "# git-nest managed hook"
done
# Subprojects must not get a pre-commit hook.
test ! -f "libs/foo/.git/hooks/pre-commit"

# --- Recursion is rejected ---
test_step "Reject recursive installation" "hooks-install takes no arguments and manages only the current nest."
run_fail "recursive install rejected" any -- sh -c '"$1" hooks-install --recursive >recursive.out 2>recursive.err' sh "$GIT_NEST"
assert_file_contains recursive.err "hooks-install takes no arguments"

# --- add auto-installs hooks into a new subproject when the nest is hooked ---
test_step "add installs hooks into a new subproject" "Because the nest root already uses managed hooks, adding a subproject installs its hooks automatically."
run_ok "second subproject added" -- "$GIT_NEST" add "$remote_bar" libs/bar
for hook in post-checkout pre-push; do
    test -f "libs/bar/.git/hooks/$hook"
    assert_file_contains "libs/bar/.git/hooks/$hook" "# git-nest managed hook"
done

describe_result "hooks-install wrote the correct hook sets, refused unmanaged hooks all-or-nothing, rejected recursion, and auto-installed hooks into a newly added subproject."
