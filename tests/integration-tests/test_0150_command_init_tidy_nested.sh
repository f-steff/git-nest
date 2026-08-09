#!/bin/sh
# Test: init creates a nest, tidy refreshes support files, and nested init requires --sure

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_init_tidy_nested

test_step "Exercise init, tidy, and nested init confirmation" "Init should create only, tidy should fix managed files, and nested nests should require explicit confirmation."

root=$(test_workspace command_init_tidy_nested)
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
test -f NEST_README.md
assert_file_contains NEST_README.md "git-nest restore"
assert_file_contains NEST_README.md "git-nest workspace"

# A maintainer edit is preserved; init never overwrites NEST_README.md.
printf '# custom nest notes\n' >NEST_README.md
"$GIT_NEST" init >init_again2.out
assert_file_contains init_again2.out "already initialized"
grep -q '# custom nest notes' NEST_README.md || {
    echo "UNEXPECTED RESULT: init overwrote the maintainer NEST_README.md" >&2
    exit 1
}

cp .gitattributes expected.gitattributes
printf 'broken\n' >.gitattributes
"$GIT_NEST" init >init_again.out
assert_file_contains init_again.out "already initialized"
assert_file_contains init_again.out "git-nest tidy"
assert_file_contains .gitattributes "broken"
"$GIT_NEST" tidy >/dev/null
assert_file_contains .gitattributes ".gitnest text eol=lf"
assert_file_contains .gitattributes "bin/git_nest.sh text eol=lf"

# tidy does not resurrect a deleted NEST_README.md (it is init-only).
rm NEST_README.md
"$GIT_NEST" tidy >/dev/null
test ! -f NEST_README.md || {
    echo "UNEXPECTED RESULT: tidy recreated NEST_README.md" >&2
    exit 1
}

"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

if (cd libs/foo && "$GIT_NEST" init >nested_init.out 2>nested_init.err); then
    echo "init inside a managed subproject should require --sure" >&2
    exit 1
fi
assert_file_contains libs/foo/nested_init.err "rerun git-nest init --sure to create an intentional nested nest"
(cd libs/foo && "$GIT_NEST" init --sure >nested_sure.out)
assert_file_contains libs/foo/nested_sure.out "Initialized git-nest workspace."
test -f libs/foo/.gitnest

describe_result "Init creates only, tidy refreshes managed files, and nested init requires --sure."
