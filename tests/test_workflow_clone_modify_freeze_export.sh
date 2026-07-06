#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin workflow_clone_modify_freeze_export

root=$(test_workspace workflow_clone_modify_freeze_export)
remote="$root/remotes/foo.git"
outer_remote="$root/remotes/outer.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
git init --bare "$outer_remote" >/dev/null
git remote add origin "$outer_remote"
git push -u origin main >/dev/null
git --git-dir="$outer_remote" symbolic-ref HEAD refs/heads/main

test_step "Clone a managed workspace" "the workflow starts from a normal consumer clone that should sync subprojects automatically."
clone="$root/clone"
run_ok "outer repository cloned with subproject checkout" -- "$GIT_LEGO" clone "$outer_remote" "$clone"
test -d "$clone/libs/foo/.git"

cd "$clone"
git -C libs/foo config user.name "git-lego test"
git -C libs/foo config user.email "git-lego@example.invalid"
printf 'end to end\n' >>libs/foo/file.txt

test_step "Commit subproject work through foreach-modified" "the workflow verifies command iteration can prepare changed subprojects."
run_ok "dirty subproject committed through foreach-modified" -- "$GIT_LEGO" foreach-modified -- sh -c '
    git add file.txt
    git commit -m "end to end export change" >/dev/null
'

test_step "Snapshot, freeze, and export deterministic archives" "the exported source package should contain the frozen workspace state reproducibly."
run_ok "local pending state refreshed without fetching" -- "$GIT_LEGO" snapshot --no-fetch
run_ok "current checkout pinned into the manifest" -- "$GIT_LEGO" freeze --force
run_ok "first deterministic export created" -- "$GIT_LEGO" export --output "$root/e2e-a.tar.gz" --deterministic
run_ok "second deterministic export created" -- "$GIT_LEGO" export --output "$root/e2e-b.tar.gz" --deterministic
cmp "$root/e2e-a.tar.gz" "$root/e2e-b.tar.gz"

mkdir "$root/e2e-extracted"
tar -xzf "$root/e2e-a.tar.gz" -C "$root/e2e-extracted"
assert_file_contains "$root/e2e-extracted/libs/foo/file.txt" "end to end"
assert_file_contains "$root/e2e-extracted/MANIFEST.lock" '[subproject "libs/foo"]'
describe_result "clone, modify, freeze, and export produced deterministic archives with the expected source and MANIFEST.lock."
