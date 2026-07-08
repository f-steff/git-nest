#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_freeze_force_dry_run

root=$(test_workspace command_freeze_force_dry_run)
remote="$root/remotes/one.git"
seed="$root/seed/one"
outer="$root/outer"
url="file://$remote"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$url" freeze/one >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
git -C freeze/one checkout -b freeze-work >/dev/null
printf 'freeze\n' >>freeze/one/file.txt
git -C freeze/one add file.txt
git -C freeze/one commit -m "freeze work" >/dev/null

test_step "Preview freezing an ahead branch" "freeze --dry-run should explain the planned pin without writing the manifest."
run_capture "dry-run described the freeze target" freeze_dry.out freeze_dry.err -- "$GIT_NEST" freeze --only freeze/one --dry-run --force
assert_file_contains freeze_dry.out 'Would freeze freeze/one'

test_step "Run freeze without force" "ahead branch tips are refused unless the user explicitly accepts pinning current HEAD."
run_fail "unsafe freeze refused" any -- sh -c '"$1" freeze --only freeze/one >freeze_refuse.out 2>freeze_refuse.err' sh "$GIT_NEST"
assert_file_contains freeze_refuse.err 'rerun with --force'

test_step "Run freeze with force" "--force pins current HEAD and leaves a warning explaining the safety override."
run_capture "forced freeze pinned current HEAD" freeze_force.out freeze_force.err -- "$GIT_NEST" freeze --only freeze/one --force
assert_file_contains freeze_force.out 'Frozen freeze/one'
assert_file_contains freeze_force.err 'freezing current HEAD'
assert_file_contains .gitnest '[subproject "freeze/one"]'
assert_file_contains .gitnest 'revision='
describe_result "freeze dry-run, refusal, and forced pinning all report clear outcomes."
