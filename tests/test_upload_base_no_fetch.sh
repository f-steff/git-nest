#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin upload_base_no_fetch

root=$(test_workspace upload_base_no_fetch)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

"$GIT_LEGO" start UPLOAD-BASE-1 >/dev/null
printf 'upload base\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "UPLOAD-BASE-1 local work" >/dev/null
base=$(git -C libs/foo rev-parse HEAD^)

awk '
    /^\[subproject "libs\/foo"\]$/ { in_section=1 }
    in_section && /^target_branch=/ { print "target_branch=missing-target"; next }
    /^\[/ && $0 != "[subproject \"libs/foo\"]" { in_section=0 }
    { print }
' .gitlego >.gitlego.tmp
mv .gitlego.tmp .gitlego
cp .gitlego before_upload_failure

if "$GIT_LEGO" upload --no-fetch >upload_fail.out 2>upload_fail.err; then
    echo "upload --no-fetch should fail when no local target ref or base override is available" >&2
    exit 1
fi
assert_file_contains upload_fail.err "cannot calculate base revision for libs/foo"
cmp .gitlego before_upload_failure >/dev/null

"$GIT_LEGO" upload --no-fetch --base libs/foo="$base" >/dev/null
assert_file_contains .gitlego "pending_branch=UPLOAD-BASE-1"
assert_file_contains .gitlego "base_revision=$base"
git --git-dir="$remote" show-ref --verify --quiet refs/heads/UPLOAD-BASE-1
