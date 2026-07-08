#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_option_upload_base_no_fetch

test_step "Exercise command option upload base no fetch" "This test verifies the documented command option upload base no fetch behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_option_upload_base_no_fetch)
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

"$GIT_NEST" start UPLOAD-BASE-1 >/dev/null
printf 'upload base\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "UPLOAD-BASE-1 local work" >/dev/null
base=$(git -C libs/foo rev-parse HEAD^)

awk '
    /^\[subproject "libs\/foo"\]$/ { in_section=1 }
    in_section && /^target_branch=/ { print "target_branch=missing-target"; next }
    /^\[/ && $0 != "[subproject \"libs/foo\"]" { in_section=0 }
    { print }
' .gitnest >.gitnest.tmp
mv .gitnest.tmp .gitnest
cp .gitnest before_upload_failure

if "$GIT_NEST" upload --no-fetch >upload_fail.out 2>upload_fail.err; then
    echo "upload --no-fetch should fail when no local target ref or base override is available" >&2
    exit 1
fi
assert_file_contains upload_fail.err "cannot calculate base revision for libs/foo"
cmp .gitnest before_upload_failure >/dev/null

"$GIT_NEST" upload --no-fetch --base libs/foo="$base" >/dev/null
assert_file_contains .gitnest "pending_branch=UPLOAD-BASE-1"
assert_file_contains .gitnest "base_revision=$base"
git --git-dir="$remote" show-ref --verify --quiet refs/heads/UPLOAD-BASE-1

describe_result "The command option upload base no fetch behavior matched the expected command output and repository state."
