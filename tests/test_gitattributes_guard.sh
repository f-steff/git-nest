#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin gitattributes_guard

root=$(test_workspace gitattributes_guard)

# init creates .gitattributes with the manifest LF guard when no file exists.
missing="$root/missing"
make_repo "$missing"
cd "$missing"
"$GIT_LEGO" init >/dev/null
printf '.gitlego text eol=lf\n' >expected_guard
cmp .gitattributes expected_guard >/dev/null

# init prepends the guard when .gitattributes exists without it.
prepend="$root/prepend"
make_repo "$prepend"
cd "$prepend"
printf '*.sh text eol=lf\n*.bat text eol=crlf\n' >.gitattributes
cp .gitattributes before
"$GIT_LEGO" init >/dev/null
{
    printf '.gitlego text eol=lf\n'
    cat before
} >expected_prepend
cmp .gitattributes expected_prepend >/dev/null

# init leaves the file byte-identical when a whitespace-equivalent guard exists.
present="$root/present"
make_repo "$present"
cd "$present"
printf '.gitlego   text   eol=lf   \n*.sh text eol=lf\n' >.gitattributes
cp .gitattributes before
"$GIT_LEGO" init >/dev/null
cmp .gitattributes before >/dev/null

# Other commands warn but do not modify .gitattributes.
warncase="$root/warn"
make_repo "$warncase"
cd "$warncase"
printf '# git-lego manifest\n[project]\nversion=1\n' >.gitlego
printf '*.sh text eol=lf\n' >.gitattributes
cp .gitattributes before
"$GIT_LEGO" status >status.out 2>status.err
assert_file_contains status.err "missing .gitattributes entry: .gitlego text eol=lf"
cmp .gitattributes before >/dev/null
