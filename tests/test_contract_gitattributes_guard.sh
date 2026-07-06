#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_gitattributes_guard

test_step "Exercise contract gitattributes guard" "This test verifies the documented contract gitattributes guard behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_gitattributes_guard)

assert_git_lego_attrs() {
    assert_file_contains .gitattributes "# BEGIN git-lego attributes"
    assert_file_contains .gitattributes ".gitlego text eol=lf"
    assert_file_contains .gitattributes ".gitlego-rc text eol=lf"
    assert_file_contains .gitattributes "bin/git-lego text eol=lf"
    assert_file_contains .gitattributes "bin/git_lego.sh text eol=lf"
    assert_file_contains .gitattributes "bin/git-lego.bat text eol=crlf"
    assert_file_contains .gitattributes "# END git-lego attributes"
}

# init creates the managed git-lego attributes block when no file exists.
missing="$root/missing"
make_repo "$missing"
cd "$missing"
"$GIT_LEGO" init >/dev/null
assert_git_lego_attrs

# init adds the managed block while preserving unrelated project attributes.
prepend="$root/prepend"
make_repo "$prepend"
cd "$prepend"
printf '*.md text\n' >.gitattributes
"$GIT_LEGO" init >/dev/null
assert_git_lego_attrs
assert_file_contains .gitattributes "*.md text"

# init leaves the file byte-identical when the full guard already exists.
present="$root/present"
make_repo "$present"
cd "$present"
"$GIT_LEGO" init >/dev/null
cp .gitattributes before
"$GIT_LEGO" init >/dev/null
cmp .gitattributes before >/dev/null

# init repairs stale/conflicting git-lego-owned entries and doctor reports them.
repair="$root/repair"
make_repo "$repair"
cd "$repair"
"$GIT_LEGO" init >/dev/null
cat >.gitattributes <<'EOF'
# BEGIN git-lego attributes
.gitlego text eol=crlf
bin/git-lego text eol=crlf
# END git-lego attributes
*.md text
EOF
"$GIT_LEGO" doctor --offline >doctor_attrs.out
assert_file_contains doctor_attrs.out "W	gitattributes	missing or stale git-lego attributes guard"
"$GIT_LEGO" init >/dev/null
assert_git_lego_attrs
assert_file_contains .gitattributes "*.md text"
assert_file_not_contains .gitattributes ".gitlego text eol=crlf"
assert_file_not_contains .gitattributes "bin/git-lego text eol=crlf"

# Other commands warn but do not modify .gitattributes.
warncase="$root/warn"
make_repo "$warncase"
cd "$warncase"
printf '# git-lego manifest\n[project]\nversion=1\n' >.gitlego
printf '*.sh text eol=lf\n' >.gitattributes
cp .gitattributes before
"$GIT_LEGO" status >status.out 2>status.err
assert_file_contains status.err "missing or stale git-lego .gitattributes guard"
cmp .gitattributes before >/dev/null

describe_result "The contract gitattributes guard behavior matched the expected command output and repository state."
