#!/bin/sh
# Test: init creates a nest, repair refreshes support files, and nested init requires --sure

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_init_repair_nested

test_step "Exercise init, repair, and nested init confirmation" "Init should create only, repair should fix managed files, and nested nests should require explicit confirmation."

root=$(test_workspace command_init_repair_nested)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
test -f .gitnest
test -f .gitattributes

cp .gitattributes expected.gitattributes
printf 'broken\n' >.gitattributes
"$GIT_NEST" init >init_again.out
assert_file_contains init_again.out "already initialized"
assert_file_contains init_again.out "git-nest repair"
assert_file_contains .gitattributes "broken"
"$GIT_NEST" repair >/dev/null
assert_file_contains .gitattributes ".gitnest text eol=lf"
assert_file_contains .gitattributes "bin/git_nest.sh text eol=lf"

"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

if (cd libs/foo && "$GIT_NEST" init >nested_init.out 2>nested_init.err); then
    echo "init inside a managed subproject should require --sure" >&2
    exit 1
fi
assert_file_contains libs/foo/nested_init.err "rerun git-nest init --sure to create an intentional nested nest"
(cd libs/foo && "$GIT_NEST" init --sure >nested_sure.out)
assert_file_contains libs/foo/nested_sure.out "Initialized git-nest workspace."
test -f libs/foo/.gitnest

describe_result "Init creates only, repair refreshes managed files, and nested init requires --sure."
