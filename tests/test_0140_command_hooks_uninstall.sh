#!/bin/sh
# Test: hooks-uninstall removes managed hooks, preserves unmanaged ones, and stops hooks firing

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_hooks_uninstall

# Uninstall must remove only git-nest-managed hooks across the nest, leave any
# unmanaged hook in place with a warning, and once removed the hooks must no
# longer fire on Git operations.
test_step "Exercise hook uninstallation" "hooks-uninstall removes the managed hook set from the root and subprojects, leaves unmanaged hooks untouched with a warning, and after removal a checkout no longer triggers git-nest."

root=$(test_workspace command_hooks_uninstall)
remote_foo="$root/remotes/foo.git"
outer="$root/outer"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_foo" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

# --- Clean uninstall removes the full managed set ---
test_step "Remove the managed hook set" "After a clean install, uninstall removes every managed hook in the root and subprojects."
"$GIT_NEST" hooks-install >/dev/null
run_ok "managed hooks removed" -- "$GIT_NEST" hooks-uninstall
for hook in post-checkout pre-commit pre-push; do
    test ! -f ".git/hooks/$hook"
done
for hook in post-checkout pre-push; do
    test ! -f "libs/foo/.git/hooks/$hook"
done

# --- After uninstall the hooks no longer fire ---
test_step "Removed hooks no longer fire" "A checkout at the nest root must not print git-nest restore guidance once the hooks are gone."
git checkout -b probe >probe.out 2>&1 || true
assert_file_not_contains probe.out "git-nest restore"
git checkout main >/dev/null 2>&1 || true

# --- Unmanaged hooks are preserved with a warning ---
test_step "Leave unmanaged hooks in place" "If a managed hook slot has been replaced by an unmanaged hook, uninstall keeps it and warns instead of deleting it."
"$GIT_NEST" hooks-install >/dev/null
# Replace the managed root pre-push with an unmanaged script.
printf '#!/bin/sh\necho custom\n' >.git/hooks/pre-push
run_capture "uninstall reports the preserved unmanaged hook" uninstall.out uninstall.err -- "$GIT_NEST" hooks-uninstall
assert_file_contains uninstall.err "leaving unmanaged hook in place"
# The unmanaged hook survives; the other managed hooks are removed.
test -f .git/hooks/pre-push
assert_file_contains .git/hooks/pre-push "echo custom"
test ! -f .git/hooks/post-checkout
test ! -f .git/hooks/pre-commit

describe_result "hooks-uninstall removed the managed set, stopped the hooks from firing, and preserved an unmanaged hook with a warning."
