#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin wave3_core_ops

root=$(test_workspace wave3_core_ops)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
remote_three="$root/remotes/three.git"
outer_remote="$root/remotes/outer.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
seed_three="$root/seed/three"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_bare_remote "$remote_three" "$seed_three"
make_repo "$outer"
url_one="file://$remote_one"
url_two="file://$remote_two"
url_three="file://$remote_three"

cd "$outer"
"$GIT_LEGO" init >/dev/null
assert_file_contains .gitignore '**/.git/'
assert_file_contains .gitignore '**/.git'
"$GIT_LEGO" add "$url_one" libs/one >/dev/null
"$GIT_LEGO" add "$url_two" libs/two >/dev/null
"$GIT_LEGO" add "$url_three" libs/three >/dev/null
cat >>.gitlego <<EOF

[extension "local"]
owner=kept
EOF
awk '
    /^\[subproject "libs\/one"\]$/ { print; print "x-extension=one"; next }
    { print }
' .gitlego >.gitlego.tmp
mv .gitlego.tmp .gitlego
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

"$GIT_LEGO" mv libs/one components/one >/dev/null
test -d components/one/.git
test ! -e libs/one
assert_file_contains .gitlego '[subproject "components/one"]'
assert_file_contains .gitlego 'x-extension=one'
assert_file_contains .gitlego '[extension "local"]'
assert_file_contains .gitignore 'components/one/'
assert_file_not_contains .gitignore 'libs/one/'

"$GIT_LEGO" mv --url "$url_one" components/one >/dev/null
assert_file_contains .gitlego "repo=$url_one"

"$GIT_LEGO" remove components/one --keep-files >keep.out
test -d components/one/.git
assert_file_not_contains .gitlego '[subproject "components/one"]'
assert_file_contains .gitignore 'components/one/'
assert_file_contains keep.out 'kept files'
"$GIT_LEGO" status --porcelain >status_unmanaged.out
assert_file_contains status_unmanaged.out 'U	components/one	unmanaged	-	-	-	nested-git-repo'
"$GIT_LEGO" verify >/dev/null 2>verify_unmanaged.err
assert_file_contains verify_unmanaged.err 'unmanaged nested Git repository'
rm -rf components/one
"$GIT_LEGO" status --porcelain >status_clean.out
assert_file_not_contains status_clean.out 'U	components/one'

printf 'dirty\n' >>libs/two/file.txt
if "$GIT_LEGO" remove libs/two >remove_dirty.out 2>remove_dirty.err; then
    echo "remove should refuse dirty subprojects" >&2
    exit 1
fi
assert_file_contains remove_dirty.err 'rerun with --force'
"$GIT_LEGO" remove libs/two --force >/dev/null
test ! -e libs/two
assert_file_not_contains .gitlego '[subproject "libs/two"]'
assert_file_not_contains .gitignore 'libs/two/'

"$GIT_LEGO" add "$url_two" libs/two >/dev/null
git -C libs/two checkout -b local-work >/dev/null
printf 'ahead\n' >>libs/two/file.txt
git -C libs/two add file.txt
git -C libs/two commit -m "local work" >/dev/null
if "$GIT_LEGO" mv libs/two moved/two >mv_dirty.out 2>mv_dirty.err; then
    echo "mv should refuse current-branch commits ahead of target" >&2
    exit 1
fi
assert_file_contains mv_dirty.err 'rerun with --force'
"$GIT_LEGO" mv libs/two moved/two --force >/dev/null
test -d moved/two/.git
assert_file_contains .gitlego '[subproject "moved/two"]'
"$GIT_LEGO" status --porcelain >status_composite.out
assert_file_contains status_composite.out 'C	moved/two	composite	-	-	-	head-differs-from-manifest'

"$GIT_LEGO" add "$url_one" freeze/one >/dev/null
git -C freeze/one checkout -b freeze-work >/dev/null
printf 'freeze\n' >>freeze/one/file.txt
git -C freeze/one add file.txt
git -C freeze/one commit -m "freeze work" >/dev/null
"$GIT_LEGO" freeze --only freeze/one --dry-run --force >freeze_dry.out 2>freeze_dry.err
assert_file_contains freeze_dry.out 'Would freeze freeze/one'
if "$GIT_LEGO" freeze --only freeze/one >freeze_refuse.out 2>freeze_refuse.err; then
    echo "freeze should refuse current-branch commits ahead of target" >&2
    exit 1
fi
"$GIT_LEGO" freeze --only freeze/one --force >freeze_force.out 2>freeze_force.err
assert_file_contains freeze_force.out 'Frozen freeze/one'
assert_file_contains freeze_force.err 'freezing current HEAD'
assert_file_contains .gitlego '[subproject "freeze/one"]'
assert_file_contains .gitlego 'revision='
git -C freeze/one push origin HEAD:freeze-work >/dev/null

git -C "$outer" init --bare "$outer_remote" >/dev/null
git -C "$outer" remote add origin "$outer_remote"
git add .gitlego .gitignore .gitattributes
git commit -m "wave3 core state" >/dev/null
git push -u origin HEAD:main >/dev/null

clone_target="$root/cloned"
"$GIT_LEGO" clone --no-sync "$outer_remote" "$clone_target" >/dev/null
test -f "$clone_target/.gitlego"
test ! -d "$clone_target/moved/two/.git"
"$GIT_LEGO" clone "$outer_remote" "$root/cloned-sync" >/dev/null
test -d "$root/cloned-sync/moved/two/.git"
