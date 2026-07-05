#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin export_command

root=$(test_workspace export_command)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null

printf '*.tmp\n' >libs/foo/.gitignore
printf 'secret.txt export-ignore\n' >libs/foo/.gitattributes
printf 'keep\n' >libs/foo/keep.txt
printf 'secret\n' >libs/foo/secret.txt
printf 'ignored\n' >libs/foo/ignored.tmp
git -C libs/foo add .gitignore .gitattributes keep.txt secret.txt
git -C libs/foo commit -m "export fixtures" >/dev/null

"$GIT_LEGO" export --output "$root/source-dir" --format dir >export_dir.out
assert_file_contains export_dir.out "Exported workspace"
test -f "$root/source-dir/.gitlego"
test -f "$root/source-dir/MANIFEST.lock"
test -f "$root/source-dir/libs/foo/file.txt"
test -f "$root/source-dir/libs/foo/keep.txt"
test ! -e "$root/source-dir/libs/foo/secret.txt"
test ! -e "$root/source-dir/libs/foo/ignored.tmp"
test ! -e "$root/source-dir/libs/foo/.git"
assert_file_contains "$root/source-dir/MANIFEST.lock" '[export]'
assert_file_contains "$root/source-dir/MANIFEST.lock" '[subproject "libs/foo"]'
assert_file_contains "$root/source-dir/MANIFEST.lock" 'revision='

"$GIT_LEGO" export --output "$root/source-with-git" --format dir --include-git >export_git.out
test -e "$root/source-with-git/libs/foo/.git"

"$GIT_LEGO" export --output "$root/source-a.tar.gz" --deterministic >export_tar_a.out
"$GIT_LEGO" export --output "$root/source-b.tar.gz" --deterministic >export_tar_b.out
cmp "$root/source-a.tar.gz" "$root/source-b.tar.gz"
tar -tzf "$root/source-a.tar.gz" >tar_list.out
assert_file_contains tar_list.out './.gitlego'
assert_file_contains tar_list.out './MANIFEST.lock'
assert_file_contains tar_list.out './libs/foo/keep.txt'
assert_file_not_contains tar_list.out './libs/foo/secret.txt'

"$GIT_LEGO" export --output "$root/source-a.zip" --deterministic >export_zip_a.out
"$GIT_LEGO" export --output "$root/source-b.zip" --deterministic >export_zip_b.out
cmp "$root/source-a.zip" "$root/source-b.zip"
python - "$root/source-a.zip" >zip_list.out <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as zf:
    for name in sorted(zf.namelist()):
        print(name)
PY
assert_file_contains zip_list.out '.gitlego'
assert_file_contains zip_list.out 'MANIFEST.lock'
assert_file_contains zip_list.out 'libs/foo/keep.txt'
assert_file_not_contains zip_list.out 'libs/foo/secret.txt'

mkdir "$root/extracted"
tar -xzf "$root/source-a.tar.gz" -C "$root/extracted"
cmp "$root/source-dir/libs/foo/keep.txt" "$root/extracted/libs/foo/keep.txt"

printf 'dirty\n' >>libs/foo/keep.txt
if "$GIT_LEGO" export --output "$root/dirty.tar.gz" >dirty_refuse.out 2>dirty_refuse.err; then
    echo "export should refuse dirty subprojects" >&2
    exit 1
fi
assert_file_contains dirty_refuse.err "dirty subprojects block export"
assert_file_contains dirty_refuse.err "libs/foo"

"$GIT_LEGO" export --output "$root/dirty-dir" --format dir --allow-dirty >dirty_allow.out
assert_file_contains "$root/dirty-dir/libs/foo/keep.txt" "dirty"
