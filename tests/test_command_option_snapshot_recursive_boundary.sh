#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_option_snapshot_recursive_boundary

test_step "Exercise command option snapshot recursive boundary" "This test verifies the documented command option snapshot recursive boundary behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_option_snapshot_recursive_boundary)
remote_firmware="$root/remotes/firmware.git"
remote_driver="$root/remotes/driver.git"
remote_extract="$root/remotes/extract.git"
seed_firmware="$root/seed/firmware"
seed_driver="$root/seed/driver"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_firmware" "$seed_firmware"
make_bare_remote "$remote_driver" "$seed_driver"
make_repo "$outer"
git -C "$outer" init --bare --initial-branch=main "$remote_extract" >/dev/null 2>&1 ||
    git -C "$outer" init --bare "$remote_extract" >/dev/null
git -C "$remote_extract" symbolic-ref HEAD refs/heads/main

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote_firmware" firmware >/dev/null
cat >firmware/.gitnest <<EOF
# git-nest manifest

[project]
version=1
EOF
: >firmware/.gitignore
git -C firmware add .gitnest .gitignore
git -C firmware commit -m "nested project manifest" >/dev/null
git -C firmware push origin main >/dev/null

(cd firmware && "$GIT_NEST" add "file://$remote_driver" drivers/io >/dev/null)
git -C firmware add .gitnest .gitignore
git -C firmware commit -m "add nested driver" >/dev/null
git -C firmware push origin main >/dev/null

git add .gitnest .gitignore .gitattributes
git commit -m "outer project" >/dev/null

if "$GIT_NEST" add "file://$remote_driver" firmware/other >boundary_add.out 2>boundary_add.err; then
    echo "add should refuse paths inside nested projects" >&2
    exit 1
fi
assert_file_contains boundary_add.err 'inside nested project firmware'

if "$GIT_NEST" config set firmware/drivers/io clone-mode partial >boundary_config.out 2>boundary_config.err; then
    echo "config should refuse paths inside nested projects from the parent" >&2
    exit 1
fi
assert_file_contains boundary_config.err 'inside nested project firmware'

if "$GIT_NEST" extract firmware "file://$remote_extract" --dry-run >boundary_extract.out 2>boundary_extract.err; then
    echo "extract should refuse nested project targets" >&2
    exit 1
fi
assert_file_contains boundary_extract.err 'contains a nested git-nest project'

if "$GIT_NEST" freeze --only firmware/drivers/io >boundary_freeze.out 2>boundary_freeze.err; then
    echo "freeze --only should refuse paths inside nested projects from the parent" >&2
    exit 1
fi
assert_file_contains boundary_freeze.err 'inside nested project firmware'

git -C firmware/drivers/io checkout -b NEST-100-driver >/dev/null
printf 'nested work\n' >>firmware/drivers/io/file.txt
git -C firmware/drivers/io add file.txt
git -C firmware/drivers/io commit -m "NEST-100 driver work" >/dev/null

cp firmware/.gitnest firmware.gitnest.before
"$GIT_NEST" snapshot >snapshot_notice.out 2>snapshot_notice.err
cmp firmware.gitnest.before firmware/.gitnest >/dev/null
assert_file_contains snapshot_notice.err 'nested project(s) have committed work not covered by this snapshot'

"$GIT_NEST" snapshot --quiet >snapshot_quiet.out 2>snapshot_quiet.err
assert_file_not_contains snapshot_quiet.err 'nested project(s) have committed work not covered by this snapshot'

"$GIT_NEST" snapshot --recursive >snapshot_recursive.out
assert_file_contains snapshot_recursive.out 'Snapshotting project: .'
assert_file_contains snapshot_recursive.out 'Snapshotting project: firmware'
assert_file_contains firmware/.gitnest 'pending_branch=NEST-100-driver'

describe_result "The command option snapshot recursive boundary behavior matched the expected command output and repository state."
