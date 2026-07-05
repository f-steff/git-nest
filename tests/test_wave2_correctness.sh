#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin wave2_correctness

root=$(test_workspace wave2_correctness)
remote="$root/remotes/foo.git"
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

# Auto-finalize must match ticket tokens, not substrings.
"$GIT_LEGO" start AB-1-token-test >/dev/null
printf 'ab1\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "subproject change" >/dev/null
"$GIT_LEGO" upload >/dev/null
git -C libs/foo checkout main >/dev/null
printf 'noise\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "ZAB-12 unrelated" >/dev/null
printf 'noise2\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "AB-12 unrelated" >/dev/null
printf 'landed\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "foo AB-1" >/dev/null
git -C libs/foo push origin main >/dev/null
git -C libs/foo checkout AB-1-token-test >/dev/null
"$GIT_LEGO" finalize libs/foo >/dev/null
if grep -F 'pending_branch=' .gitlego >/dev/null; then
    echo "token-bound auto-finalize did not finalize pending state" >&2
    exit 1
fi

# Removing the HEAD^ fallback should make unresolved target branches fail until
# an explicit base is supplied.
git -C libs/foo checkout -b BASE-1 >/dev/null
printf 'base\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "BASE-1 local work" >/dev/null
base=$(git -C libs/foo rev-parse HEAD^)
awk '
    /^\[subproject "libs\/foo"\]$/ { in_section=1 }
    in_section && /^repo=/ && !done { print; print "target_branch=missing-target"; done=1; next }
    /^\[/ && $0 != "[subproject \"libs/foo\"]" { in_section=0 }
    { print }
' .gitlego >.gitlego.tmp
mv .gitlego.tmp .gitlego
cp .gitlego before_base_failure
if "$GIT_LEGO" snapshot >base_fail.out 2>base_fail.err; then
    echo "snapshot should fail when target/base cannot be resolved" >&2
    exit 1
fi
assert_file_contains base_fail.err "cannot calculate base revision for libs/foo"
cmp .gitlego before_base_failure >/dev/null
"$GIT_LEGO" snapshot --base libs/foo="$base" >/dev/null
assert_file_contains .gitlego "base_revision=$base"
git -C libs/foo checkout main >/dev/null
git -C libs/foo branch -D BASE-1 >/dev/null
main_revision=$(git -C libs/foo rev-parse HEAD)
cat >.gitlego <<EOF
# git-lego manifest

[project]
version=1
id=AB-1
branch=AB-1-token-test

[subproject "libs/foo"]
repo=$remote
target_branch=main
revision=$main_revision
EOF

# sync must detect remote tag drift before checking out a moved tag.
git -C "$seed" tag -f v-drift "$(git -C "$seed" rev-parse HEAD)" >/dev/null
git -C "$seed" push -f origin v-drift >/dev/null
"$GIT_LEGO" update libs/foo --tag v-drift >/dev/null
recorded=$(sed -n 's/^revision=//p' .gitlego | sed -n '1p')
head_before=$(git -C libs/foo rev-parse HEAD)
printf 'drift\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "move drift tag" >/dev/null
git -C "$seed" tag -f v-drift HEAD >/dev/null
git -C "$seed" push -f origin v-drift >/dev/null
if "$GIT_LEGO" sync >tag_drift.out 2>tag_drift.err; then
    echo "sync should fail when a remote tag moved away from recorded revision" >&2
    exit 1
fi
assert_file_contains tag_drift.err "tag/revision mismatch for libs/foo"
test "$(git -C libs/foo rev-parse HEAD)" = "$head_before"
"$GIT_LEGO" sync --force >tag_force.out 2>tag_force.err
assert_file_contains tag_force.err "--force is proceeding"
test "$recorded" != "$(git -C "$seed" rev-parse HEAD)"
