#!/bin/sh
# Test: move/mv and remove/detach update path state and enforce safety

set -eu
. "$(dirname "$0")/helper.sh"
test_begin symmetry_mv_remove

root=$(test_workspace symmetry_mv_remove)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
outer="$root/outer"
url_one="file://$remote_one"
url_two="file://$remote_two"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$url_one" libs/one >/dev/null
"$GIT_NEST" add "$url_two" libs/two >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Move a clean subproject path" "move should update checkout location, manifest section, and ignore entry together."
run_ok "clean subproject moved to components/one" -- "$GIT_NEST" move libs/one components/one
test -d components/one/.git
test ! -e libs/one
assert_file_contains .gitnest '[subproject "components/one"]'
assert_file_contains .gitignore 'components/one/'
assert_file_not_contains .gitignore 'libs/one/'

test_step "Retarget the moved subproject URL" "move --url is the symmetric URL-only retarget operation."
run_ok "manifest URL updated without moving files" -- "$GIT_NEST" move --url "$url_one" components/one
assert_file_contains .gitnest "repo=$url_one"

test_step "Detach while keeping files" "detach should remove a subproject from the nest without letting the outer repo track it, and reject the retired remove --keep-files flag."
# remove --keep-files was retired in favor of the dedicated detach command; make
# sure the old flag fails with guidance instead of silently keeping files.
run_fail "retired remove --keep-files rejected with guidance" any -- sh -c '"$1" remove components/one --keep-files >keepfiles.out 2>keepfiles.err' sh "$GIT_NEST"
assert_file_contains keepfiles.err 'use git-nest detach'
run_ok "subproject detached and checkout kept ignored" -- "$GIT_NEST" detach components/one
test -d components/one/.git
assert_file_not_contains .gitnest '[subproject "components/one"]'
assert_file_contains .gitignore 'components/one/'
run_capture "status reports the kept checkout as unmanaged" status_unmanaged.out status_unmanaged.err -- "$GIT_NEST" status --porcelain
assert_file_contains status_unmanaged.out 'U	components/one	unmanaged	-	-	-	nested-git-repo'

test_step "Refuse unsafe remove and move unless forced" "dirty or ahead checkouts need an explicit safety override."
printf 'dirty\n' >>libs/two/file.txt
run_fail "dirty subproject removal refused" any -- sh -c '"$1" remove libs/two >remove_dirty.out 2>remove_dirty.err' sh "$GIT_NEST"
assert_file_contains remove_dirty.err 'rerun with --force'
run_ok "dirty subproject removed after explicit --force" -- "$GIT_NEST" remove libs/two --force
test ! -e libs/two
assert_file_not_contains .gitnest '[subproject "libs/two"]'
assert_file_not_contains .gitignore 'libs/two/'

"$GIT_NEST" add "$url_two" libs/two >/dev/null
git -C libs/two checkout -b local-work >/dev/null
printf 'ahead\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "local work" >/dev/null
run_fail "ahead subproject move refused" any -- sh -c '"$1" mv libs/two moved/two >mv_dirty.out 2>mv_dirty.err' sh "$GIT_NEST"
assert_file_contains mv_dirty.err 'rerun with --force'
run_ok "ahead subproject moved after explicit --force" -- "$GIT_NEST" mv libs/two moved/two --force
test -d moved/two/.git
assert_file_contains .gitnest '[subproject "moved/two"]'
describe_result "move/mv and remove/rm update path state together and require --force for unsafe local state."
