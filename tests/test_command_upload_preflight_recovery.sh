#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_upload_preflight_recovery

test_step "Exercise command upload preflight recovery" "This test verifies the documented command upload preflight recovery behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace command_upload_preflight_recovery)
remote_one="$work/remotes/one.git"
remote_two="$work/remotes/two.git"
seed_one="$work/seed/one"
seed_two="$work/seed/two"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote_one" libs/one >/dev/null
"$GIT_NEST" add "$remote_two" libs/two >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
"$GIT_NEST" start XX-501-upload-preflight >/dev/null

git -C libs/one checkout -b one/XX-501 >/dev/null
printf 'one\n' >>libs/one/file.txt
git -C libs/one add file.txt
git -C libs/one commit -m "XX-501 one work" >/dev/null

git -C libs/two checkout -b two/XX-501 >/dev/null
printf 'two\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "XX-501 two work" >/dev/null
git -C libs/two remote remove origin

if "$GIT_NEST" upload >upload.out 2>upload.err; then
    echo "upload should fail before pushing any subproject when one changed subproject cannot push" >&2
    exit 1
fi

assert_file_contains upload.err "subproject libs/two has no origin remote; restore or add origin, then rerun git-nest upload"
assert_file_not_contains .gitnest "pending_branch=one/XX-501"
assert_file_not_contains .gitnest "pending_branch=two/XX-501"
if git --git-dir="$remote_one" show-ref --verify --quiet refs/heads/one/XX-501; then
    echo "upload pushed libs/one before preflighting libs/two" >&2
    exit 1
fi

git -C libs/two remote add origin "$remote_two"
"$GIT_NEST" upload >retry.out
assert_file_contains retry.out "Uploaded subproject libs/one branch one/XX-501"
assert_file_contains retry.out "Uploaded subproject libs/two branch two/XX-501"
assert_file_contains .gitnest "pending_branch=one/XX-501"
assert_file_contains .gitnest "pending_branch=two/XX-501"

describe_result "The command upload preflight recovery behavior matched the expected command output and repository state."
