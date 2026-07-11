#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_hooks_install_uninstall

test_step "Exercise hook install and uninstall" "Hooks should be symmetric, nest-aware, and limited to the supported root and subproject hook sets."

root=$(test_workspace command_hooks_install_uninstall)
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

(cd libs/foo && "$GIT_NEST" hooks-install >/dev/null)
for hook in post-checkout pre-commit pre-push; do
    test -f ".git/hooks/$hook"
    assert_file_contains ".git/hooks/$hook" "# git-nest managed hook"
done
for hook in post-checkout pre-push; do
    test -f "libs/foo/.git/hooks/$hook"
    assert_file_contains "libs/foo/.git/hooks/$hook" "# git-nest managed hook"
done
test ! -f "libs/foo/.git/hooks/pre-commit"

if "$GIT_NEST" hooks-install --recursive >hooks_bad.out 2>hooks_bad.err; then
    echo "hooks-install should reject recursive installation" >&2
    exit 1
fi
assert_file_contains hooks_bad.err "hooks-install takes no arguments"

"$GIT_NEST" hooks-uninstall >/dev/null
for hook in post-checkout pre-commit pre-push; do
    test ! -f ".git/hooks/$hook"
done
for hook in post-checkout pre-push; do
    test ! -f "libs/foo/.git/hooks/$hook"
done

printf '#!/bin/sh\n' >.git/hooks/pre-push
if "$GIT_NEST" hooks-install >hooks_unmanaged.out 2>hooks_unmanaged.err; then
    echo "hooks-install should refuse unmanaged hooks" >&2
    exit 1
fi
assert_file_contains hooks_unmanaged.err "refusing to overwrite unmanaged hook"
test ! -f ".git/hooks/post-checkout"

describe_result "Hook installation and uninstallation respected root/subproject symmetry and unmanaged hook safety."
