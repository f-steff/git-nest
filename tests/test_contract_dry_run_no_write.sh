#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_dry_run_no_write

test_step "Exercise contract dry run no write" "This test verifies the documented contract dry run no write behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_dry_run_no_write)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
(cd libs/foo && git_config)
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

old_origin=$(git -C libs/foo rev-parse origin/main)
old_manifest=$(git hash-object .gitnest)

printf 'remote advance\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "advance main" >/dev/null
git -C "$seed" push origin main >/dev/null
new_origin=$(git --git-dir="$remote" rev-parse refs/heads/main)
test "$old_origin" != "$new_origin"

"$GIT_NEST" sync --dry-run >sync.out
assert_file_contains sync.out "[dry-run]"
test "$(git -C libs/foo rev-parse origin/main)" = "$old_origin"

git -C libs/foo checkout -b DRY-1 >/dev/null
printf 'local work\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "DRY-1 local work" >/dev/null

"$GIT_NEST" snapshot --dry-run >snapshot.out
assert_file_contains snapshot.out "[dry-run]"
test "$(git hash-object .gitnest)" = "$old_manifest"
test ! -e .gitnest.lock
test "$(git -C libs/foo rev-parse origin/main)" = "$old_origin"

"$GIT_NEST" upload --dry-run >upload.out
assert_file_contains upload.out "[dry-run] would push subproject libs/foo branch DRY-1"
test "$(git hash-object .gitnest)" = "$old_manifest"
test "$(git -C libs/foo rev-parse origin/main)" = "$old_origin"

"$GIT_NEST" upload --no-fetch --base libs/foo="$old_origin" >/dev/null
pending_manifest=$(git hash-object .gitnest)
"$GIT_NEST" finalize libs/foo --dry-run --use-target-head >finalize.out
assert_file_contains finalize.out "[dry-run] libs/foo revision:"
assert_file_contains finalize.out "$new_origin"
test "$(git hash-object .gitnest)" = "$pending_manifest"
test ! -e .gitnest.lock
test "$(git -C libs/foo rev-parse origin/main)" = "$old_origin"

describe_result "The contract dry run no write behavior matched the expected command output and repository state."
