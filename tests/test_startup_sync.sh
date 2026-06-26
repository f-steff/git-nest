#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin startup_sync

root=$(test_workspace startup_sync)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"

# Build two usable remotes for copied-manifest startup and sync scenarios.
mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"

# An empty folder can be turned directly into a stack branch.
empty="$root/empty"
mkdir -p "$empty"
cd "$empty"
"$GIT_STACK" start XX-100-empty >/dev/null
test -d .git
test -f .stack
test ! -f .stack-rc
test "$(git branch --show-current)" = "XX-100-empty"
assert_file_contains .stack "branch=XX-100-empty"

# A file-only folder is also allowed without --sure.
file_only="$root/file_only"
mkdir -p "$file_only"
printf 'local notes\n' >"$file_only/notes.txt"
cd "$file_only"
"$GIT_STACK" start XX-101-files >/dev/null
test -f notes.txt
test -f .stack
test ! -f .stack-rc
test "$(git branch --show-current)" = "XX-101-files"

# Subdirectories in a non-Git startup folder require explicit confirmation.
with_subdir="$root/with_subdir"
mkdir -p "$with_subdir/existing"
cd "$with_subdir"
if "$GIT_STACK" start XX-102-subdir >subdir.out 2>subdir.err </dev/null; then
    echo "start should require --sure when a new workspace contains subdirectories" >&2
    exit 1
fi
assert_file_contains subdir.err "rerun with --sure"
"$GIT_STACK" start XX-102-subdir --sure >/dev/null
test -d .git
test -f .stack
test ! -f .stack-rc

# A copied .stack can bootstrap module checkouts in an otherwise empty folder.
sync_ok="$root/sync_ok"
mkdir -p "$sync_ok"
cat >"$sync_ok/.stack" <<EOF
# git-stack manifest

[stack]

[module "libs/one"]
repo=$remote_one
target_branch=main

[module "libs/two"]
repo=$remote_two
target_branch=main
EOF
cd "$sync_ok"
"$GIT_STACK" sync >/dev/null
test -d libs/one/.git
test -d libs/two/.git

# Sync should attempt every module, keep successful clones, then fail clearly.
sync_partial="$root/sync_partial"
mkdir -p "$sync_partial"
cat >"$sync_partial/.stack" <<EOF
# git-stack manifest

[stack]

[module "libs/one"]
repo=$remote_one
target_branch=main

[module "libs/missing"]
repo=$root/remotes/missing.git
target_branch=main
EOF
cd "$sync_partial"
if "$GIT_STACK" sync >sync.out 2>sync.err; then
    echo "sync should fail after attempting all modules when one clone fails" >&2
    exit 1
fi
test -d libs/one/.git
test ! -d libs/missing/.git
assert_file_contains sync.err "Error: sync failed for one or more modules"
assert_file_contains sync.err "libs/missing"
