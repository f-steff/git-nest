#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin gitignore_dedup

root=$(test_workspace gitignore_dedup)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"

slash="$root/slash"
make_repo "$slash"
cd "$slash"
"$GIT_LEGO" init >/dev/null
printf 'libs/foo/\n' >.gitignore
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
test "$(grep -c '^libs/foo/$' .gitignore)" = "1"

noslash="$root/noslash"
make_repo "$noslash"
cd "$noslash"
"$GIT_LEGO" init >/dev/null
printf 'libs/foo\n' >.gitignore
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
test "$(grep -c '^libs/foo$' .gitignore)" = "1"
if grep -q '^libs/foo/$' .gitignore; then
    echo "add should respect existing no-slash gitignore entry" >&2
    exit 1
fi

absent="$root/absent"
make_repo "$absent"
cd "$absent"
"$GIT_LEGO" init >/dev/null
printf '*.tmp' >.gitignore
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
printf '*.tmp\n**/.git/\n**/.git\nlibs/foo/\n' >expected
cmp .gitignore expected >/dev/null
