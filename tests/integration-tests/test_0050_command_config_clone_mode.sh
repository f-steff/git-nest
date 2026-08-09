#!/bin/sh
# Test: config get/set/list/unset for clone-mode with validation

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_config_clone_mode

work=$(test_workspace command_config_clone_mode)
remote="$work/remotes/one.git"
seed="$work/seed/one"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/one >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

test_step "Read unset clone-mode" "config get should distinguish absent manifest settings from explicit values."
run_fail "unset clone-mode returned nonzero" 1 -- sh -c '"$1" config get libs/one clone-mode >config_unset.out 2>config_unset.err' sh "$GIT_NEST"

test_step "Set, list, and unset clone-mode" "config writes only the manifest and warns that existing checkouts are not converted."
run_capture "clone-mode set to partial" config_set.out config_set.err -- "$GIT_NEST" config set libs/one clone-mode partial
assert_file_contains config_set.err "existing checkouts are not converted"
assert_file_contains .gitnest "clone=partial"
test "$("$GIT_NEST" config get libs/one clone-mode)" = "partial"
run_capture "clone-mode listed" config_list.out config_list.err -- "$GIT_NEST" config list
assert_file_contains config_list.out "libs/one	clone-mode=partial"
run_ok "clone-mode removed from manifest" -- "$GIT_NEST" config unset libs/one clone-mode
assert_file_not_contains .gitnest "clone=partial"

test_step "Reject invalid config inputs" "only allowlisted keys and clone-mode values should be accepted."
run_fail "invalid clone-mode rejected" any -- sh -c '"$1" config set libs/one clone-mode somethingsomething >config_bad_value.out 2>config_bad_value.err' sh "$GIT_NEST"
assert_file_contains config_bad_value.err "clone-mode must be full or partial"
run_fail "unknown config key rejected" any -- sh -c '"$1" config get libs/one unknown-key >config_bad_key.out 2>config_bad_key.err' sh "$GIT_NEST"
assert_file_contains config_bad_key.err "unknown config key"
run_fail "repo cannot be unset through config" any -- sh -c '"$1" config unset libs/one repo >config_unset_repo.out 2>config_unset_repo.err' sh "$GIT_NEST"
assert_file_contains config_unset_repo.err "unknown config key: repo"

test_step "Reject invalid lock timeout and report configured lock waits" "manifest writers should not hide hardcoded lock waits."
run_fail "invalid lock timeout environment rejected" any -- sh -c 'GIT_NEST_LOCK_TIMEOUT_SECONDS=bad "$1" config set libs/one clone-mode full >config_bad_lock_timeout.out 2>config_bad_lock_timeout.err' sh "$GIT_NEST"
assert_file_contains config_bad_lock_timeout.err "GIT_NEST_LOCK_TIMEOUT_SECONDS requires a positive integer"
mkdir .gitnest.lock
printf 'pid=999999\ncreated_utc=2026-07-08T00:00:00Z\n' >.gitnest.lock/info
run_fail "held manifest lock uses configured wait" 4 -- sh -c 'GIT_NEST_LOCK_TIMEOUT_SECONDS=1 "$1" config set libs/one clone-mode full >config_lock_wait.out 2>config_lock_wait.err' sh "$GIT_NEST"
assert_file_contains config_lock_wait.err "after 1 seconds"
rm -rf .gitnest.lock
describe_result "config clone-mode get/set/list/unset and validation behaved as documented."
