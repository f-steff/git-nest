#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin clone_verify_root

work=$(test_workspace clone_verify_root)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

# Exercise Git external-command discovery for the new commands in this test.
PATH="$REPO_ROOT/bin:$PATH"
export PATH

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
git --git-dir="$remote" config uploadpack.allowFilter true
git --git-dir="$remote" config uploadpack.allowAnySHA1InWant true
remote_url="file://$remote"
work=$(test_workspace clone_verify_root)

make_repo "$outer"
cd "$outer"
git lego init --rc >/dev/null
git lego add --clone partial "$remote_url" libs/foo >/dev/null

assert_file_contains .gitlego 'clone=partial'
test "$(git -C libs/foo config --get remote.origin.promisor)" = "true"
test "$(git -C libs/foo config --get remote.origin.partialclonefilter)" = "blob:none"
git lego verify >/dev/null

# Commands invoked from deep inside a subproject must still operate on the outer project.
mkdir -p libs/foo/a/b/c
cd libs/foo/a/b/c
git lego status >"$work/status_from_deep.txt"
git lego verify >"$work/verify_from_deep.txt"
assert_file_contains "$work/status_from_deep.txt" "libs/foo:"
assert_file_contains "$work/verify_from_deep.txt" "Project verified."
cd "$outer"

# A global full-clone override should make verify flag the existing partial clone.
sed 's/^mode=manifest$/mode=full/' .gitlego-rc >.gitlego-rc.tmp
mv .gitlego-rc.tmp .gitlego-rc
if git lego verify >verify_full.out 2>verify_full.err; then
    echo "verify should fail when global full mode sees a partial checkout" >&2
    exit 1
fi
assert_file_contains verify_full.err "requests clone=full"
sed 's/^mode=full$/mode=manifest/' .gitlego-rc >.gitlego-rc.tmp
mv .gitlego-rc.tmp .gitlego-rc

# Sync from only a copied manifest must recreate the partial checkout.
revision=$(git -C libs/foo rev-parse HEAD)
sync_partial="$work/sync_partial"
mkdir -p "$sync_partial"
cp .gitlego .gitlego-rc "$sync_partial/"
cd "$sync_partial"
git lego sync >/dev/null
test "$(git -C libs/foo config --get remote.origin.promisor)" = "true"
test "$(git -C libs/foo config --get remote.origin.partialclonefilter)" = "blob:none"
test "$(git -C libs/foo rev-parse HEAD)" = "$revision"
git lego verify >/dev/null

# A global partial override should partial-clone subprojects without per-subproject clone keys.
sync_global_partial="$work/sync_global_partial"
mkdir -p "$sync_global_partial"
cat >"$sync_global_partial/.gitlego" <<EOF
# git-lego manifest

[project]
version=1

[subproject "libs/foo"]
repo=$remote_url
target_branch=main
revision=$revision
EOF
cat >"$sync_global_partial/.gitlego-rc" <<EOF
[clone]
mode=partial
EOF
cd "$sync_global_partial"
git lego sync >/dev/null
test "$(git -C libs/foo config --get remote.origin.promisor)" = "true"
git lego verify >/dev/null

# A global full override should ignore a subproject-level partial request.
sync_global_full="$work/sync_global_full"
mkdir -p "$sync_global_full"
cat >"$sync_global_full/.gitlego" <<EOF
# git-lego manifest

[project]
version=1

[subproject "libs/foo"]
repo=$remote_url
clone=partial
target_branch=main
revision=$revision
EOF
cat >"$sync_global_full/.gitlego-rc" <<EOF
[clone]
mode=full
EOF
cd "$sync_global_full"
git lego sync >/dev/null
if git -C libs/foo config --get remote.origin.promisor >/dev/null 2>&1; then
    echo "global full clone override should not create a partial clone" >&2
    exit 1
fi
git lego verify >/dev/null

# Invalid clone settings must fail clearly.
invalid="$work/invalid_clone_mode"
mkdir -p "$invalid"
cat >"$invalid/.gitlego" <<EOF
# git-lego manifest

[project]
version=1

[subproject "libs/foo"]
repo=$remote_url
clone=tiny
target_branch=main
EOF
cd "$invalid"
if git lego verify >invalid.out 2>invalid.err; then
    echo "verify should fail for an invalid subproject clone mode" >&2
    exit 1
fi
assert_file_contains invalid.err "clone mode"
