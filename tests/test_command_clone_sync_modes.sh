#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_clone_sync_modes

root=$(test_workspace command_clone_sync_modes)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
outer_remote="$root/remotes/outer.git"
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
"$GIT_NEST" add "$url_two" moved/two >/dev/null
git -C "$outer" init --bare "$outer_remote" >/dev/null
git -C "$outer" remote add origin "$outer_remote"
git add .gitnest .gitignore .gitattributes
git commit -m "clone sync modes state" >/dev/null
git push -u origin HEAD:main >/dev/null
git --git-dir="$outer_remote" symbolic-ref HEAD refs/heads/main

test_step "Clone without automatic sync" "clone --no-sync should materialize only the outer repository."
clone_target="$root/cloned"
run_ok "outer repository cloned without subproject checkout" -- "$GIT_NEST" clone --no-sync "$outer_remote" "$clone_target"
test -f "$clone_target/.gitnest"
test ! -d "$clone_target/moved/two/.git"

test_step "Clone with automatic sync" "plain clone should run sync when the outer repository contains .gitnest."
run_ok "outer repository cloned and subprojects synced" -- "$GIT_NEST" clone "$outer_remote" "$root/cloned-sync"
test -d "$root/cloned-sync/moved/two/.git"
describe_result "clone respected --no-sync and performed automatic sync by default."
