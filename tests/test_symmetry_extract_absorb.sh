#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin symmetry_extract_absorb

test_step "Exercise symmetry extract absorb" "This test verifies the documented symmetry extract absorb behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace symmetry_extract_absorb)
outer="$root/outer"
remote_extracted="$root/remotes/extracted.git"
remote_nonempty="$root/remotes/nonempty.git"
remote_forced="$root/remotes/forced.git"

mkdir -p "$root/remotes"
make_repo "$outer"
git -C "$outer" init --bare --initial-branch=main "$remote_extracted" >/dev/null 2>&1 ||
    git -C "$outer" init --bare "$remote_extracted" >/dev/null
git -C "$remote_extracted" symbolic-ref HEAD refs/heads/main
make_bare_remote "$remote_nonempty" "$root/seed/nonempty"
git -C "$outer" init --bare --initial-branch=main "$remote_forced" >/dev/null 2>&1 ||
    git -C "$outer" init --bare "$remote_forced" >/dev/null
git -C "$remote_forced" symbolic-ref HEAD refs/heads/main

cd "$outer"
"$GIT_NEST" init >/dev/null
mkdir -p src/lib
printf 'one\n' >src/lib/one.txt
printf 'two\n' >src/lib/two.txt
mkdir -p src/nonempty
printf 'remote check\n' >src/nonempty/file.txt
mkdir -p hist/lib
printf 'history\n' >hist/lib/file.txt
git add .gitnest .gitignore .gitattributes src/lib src/nonempty hist/lib
git commit -m "initial outer files" >/dev/null

if ! command -v git-filter-repo >/dev/null 2>&1; then
    if "$GIT_NEST" extract hist/lib "file://$remote_extracted" --preserve-history >preserve.out 2>preserve.err; then
        echo "extract --preserve-history should fail when git-filter-repo is missing" >&2
        exit 1
    fi
    assert_file_contains preserve.err 'requires git-filter-repo'
    assert_file_not_contains .gitnest '[subproject "hist/lib"]'
    test ! -d .gitnest-extract-backup
fi

if "$GIT_NEST" extract src/nonempty "file://$remote_nonempty" --push >nonempty.out 2>nonempty.err; then
    echo "extract --push should refuse a non-empty remote" >&2
    exit 1
fi
assert_file_contains nonempty.err 'overriding non-empty remotes is deliberately not implemented'
assert_file_not_contains .gitnest '[subproject "src/nonempty"]'

"$GIT_NEST" extract src/lib "file://$remote_extracted" --push --message "initial extracted lib" >extract.out
test -d src/lib/.git
assert_file_contains .gitnest '[subproject "src/lib"]'
assert_file_contains .gitnest "repo=file://$remote_extracted"
assert_file_contains .gitignore 'src/lib/'
assert_file_contains extract.out 'Extracted src/lib as a git-nest subproject'
git -C src/lib rev-parse --verify main >/dev/null
git --git-dir="$remote_extracted" rev-parse --verify main >/dev/null
git diff --cached --name-status >extract_staged.out
assert_file_contains extract_staged.out 'D	src/lib/one.txt'
assert_file_contains extract_staged.out 'D	src/lib/two.txt'
assert_file_contains extract_staged.out 'M	.gitnest'
test ! -d .gitnest-extract-backup

git commit -m "extract lib" >/dev/null
"$GIT_NEST" absorb src/lib >absorb.out
test ! -e src/lib/.git
assert_file_not_contains .gitnest '[subproject "src/lib"]'
assert_file_not_contains .gitignore 'src/lib/'
assert_file_contains absorb.out 'Absorbed src/lib into the outer repository'
git diff --cached --name-status >absorb_staged.out
assert_file_contains absorb_staged.out 'A	src/lib/one.txt'
assert_file_contains absorb_staged.out 'A	src/lib/two.txt'
test ! -d .gitnest-absorb-backup

if "$GIT_NEST" extract src/lib "file://$remote_forced" --dry-run >dirty_staged.out 2>dirty_staged.err; then
    echo "extract should refuse staged outer changes without --force" >&2
    exit 1
fi
assert_file_contains dirty_staged.err 'staged outer-repository changes'

git commit -m "absorb lib" >/dev/null
printf 'fresh\n' >src/lib/fresh.txt
if "$GIT_NEST" extract src/lib "file://$remote_forced" >fresh.out 2>fresh.err; then
    echo "extract should refuse untracked files" >&2
    exit 1
fi
assert_file_contains fresh.err 'commit these files in the outer repo first'
rm src/lib/fresh.txt

printf 'unstaged\n' >>src/lib/one.txt
if "$GIT_NEST" extract src/lib "file://$remote_forced" >unstaged.out 2>unstaged.err; then
    echo "extract should refuse unstaged outer changes" >&2
    exit 1
fi
assert_file_contains unstaged.err 'commit these files in the outer repo first'
git checkout -- src/lib/one.txt

printf 'staged override\n' >>src/lib/one.txt
git add src/lib/one.txt
"$GIT_NEST" extract src/lib "file://$remote_forced" --force --message "forced staged extraction" >force_extract.out
test -d src/lib/.git
assert_file_contains force_extract.out 'Extracted src/lib as a git-nest subproject'
assert_file_contains .gitnest '[subproject "src/lib"]'
test ! -d .gitnest-extract-backup

"$GIT_NEST" extract src/nonempty "file://$remote_extracted" --dry-run >dry.out
assert_file_contains dry.out 'Would extract src/nonempty'
test ! -d .gitnest-extract-backup

git -C src/lib push -u origin main >/dev/null
mkdir -p .git/hooks
cat >.git/hooks/pre-commit <<'HOOK'
#!/bin/sh
echo "blocking absorb commit" >&2
exit 1
HOOK
chmod +x .git/hooks/pre-commit
if "$GIT_NEST" absorb src/lib --commit >absorb_commit_fail.out 2>absorb_commit_fail.err; then
    echo "absorb --commit should surface recovery guidance when commit fails after backup" >&2
    exit 1
fi
assert_file_contains absorb_commit_fail.err 'backup is in .gitnest-absorb-backup'
assert_file_contains absorb_commit_fail.err 'restore .gitnest-absorb-backup'
test ! -e src/lib/.git
test -d .gitnest-absorb-backup

describe_result "The symmetry extract absorb behavior matched the expected command output and repository state."
