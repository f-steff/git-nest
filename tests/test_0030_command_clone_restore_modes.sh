#!/bin/sh
# Test: clone honors --no-restore and otherwise restores subprojects automatically

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_clone_restore_modes

root=$(test_workspace command_clone_restore_modes)
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
git commit -m "clone restore modes state" >/dev/null
git push -u origin HEAD:main >/dev/null
git --git-dir="$outer_remote" symbolic-ref HEAD refs/heads/main

test_step "Clone without automatic restore" "clone --no-restore should materialize only the outer repository."
clone_target="$root/cloned"
run_ok "outer repository cloned without subproject checkout" -- "$GIT_NEST" clone --no-restore "$outer_remote" "$clone_target"
test -f "$clone_target/.gitnest"
test ! -d "$clone_target/moved/two/.git"

test_step "Clone with automatic restore" "plain clone should run restore when the outer repository contains .gitnest."
run_ok "outer repository cloned and subprojects restored" -- "$GIT_NEST" clone "$outer_remote" "$root/cloned-restore"
test -d "$root/cloned-restore/moved/two/.git"
describe_result "clone respected --no-restore and performed automatic restore by default."
