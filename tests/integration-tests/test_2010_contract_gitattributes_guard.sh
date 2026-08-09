#!/bin/sh
# Test: the managed .gitattributes guard block is created and repaired

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_gitattributes_guard

test_step "Exercise contract gitattributes guard" "This test verifies the documented contract gitattributes guard behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_gitattributes_guard)

assert_git_nest_attrs() {
    assert_file_contains .gitattributes "# BEGIN git-nest attributes"
    assert_file_contains .gitattributes ".gitnest text eol=lf"
    assert_file_contains .gitattributes ".gitnest-rc text eol=lf"
    assert_file_contains .gitattributes "bin/git-nest text eol=lf"
    assert_file_contains .gitattributes "bin/git-nest-main.sh text eol=lf"
    assert_file_contains .gitattributes "bin/git-nest.bat text eol=crlf"
    assert_file_contains .gitattributes "# END git-nest attributes"
}

# init creates the managed git-nest attributes block when no file exists.
missing="$root/missing"
make_repo "$missing"
cd "$missing"
"$GIT_NEST" init >/dev/null
assert_git_nest_attrs

# init adds the managed block while preserving unrelated project attributes.
prepend="$root/prepend"
make_repo "$prepend"
cd "$prepend"
printf '*.md text\n' >.gitattributes
"$GIT_NEST" init >/dev/null
assert_git_nest_attrs
assert_file_contains .gitattributes "*.md text"

# init leaves the file byte-identical when the full guard already exists.
present="$root/present"
make_repo "$present"
cd "$present"
"$GIT_NEST" init >/dev/null
cp .gitattributes before
"$GIT_NEST" init >/dev/null
cmp .gitattributes before >/dev/null

# tidy refreshes stale/conflicting git-nest-owned entries and doctor reports them.
tidy="$root/tidy"
make_repo "$tidy"
cd "$tidy"
"$GIT_NEST" init >/dev/null
cat >.gitattributes <<'EOF'
# BEGIN git-nest attributes
.gitnest text eol=crlf
bin/git-nest text eol=crlf
# END git-nest attributes
*.md text
EOF
"$GIT_NEST" doctor --offline >doctor_attrs.out
assert_file_contains doctor_attrs.out "W	gitattributes	missing or stale git-nest attributes guard"
"$GIT_NEST" tidy >/dev/null
assert_git_nest_attrs
assert_file_contains .gitattributes "*.md text"
assert_file_not_contains .gitattributes ".gitnest text eol=crlf"
assert_file_not_contains .gitattributes "bin/git-nest text eol=crlf"

# Other commands warn but do not modify .gitattributes.
warncase="$root/warn"
make_repo "$warncase"
cd "$warncase"
printf '# git-nest manifest\n[project]\nversion=1\n' >.gitnest
printf '*.sh text eol=lf\n' >.gitattributes
cp .gitattributes before
"$GIT_NEST" status >status.out 2>status.err
assert_file_contains status.err "missing or stale git-nest .gitattributes guard"
cmp .gitattributes before >/dev/null

describe_result "The contract gitattributes guard behavior matched the expected command output and repository state."
