#!/bin/sh
# Test: absorb (files) and inline round-trip and both reject unsafe states

set -eu
. "$(dirname "$0")/helper.sh"
test_begin symmetry_absorb_inline

# absorb (files source) and inline are the symmetric pair for the outer-file
# lifecycle: absorb turns tracked outer files into a managed subproject, and
# inline dissolves a managed subproject back into ordinary outer-repo files.
test_step "Exercise absorb (files) and inline symmetry" "This test verifies that absorbing outer-repository files and inlining them back is reversible, and that both refuse unsafe repository states."

root=$(test_workspace symmetry_absorb_inline)
outer="$root/outer"
remote_absorbed="$root/remotes/absorbed.git"
remote_nonempty="$root/remotes/nonempty.git"
remote_forced="$root/remotes/forced.git"

mkdir -p "$root/remotes"
make_repo "$outer"
git -C "$outer" init --bare --initial-branch=main "$remote_absorbed" >/dev/null 2>&1 ||
    git -C "$outer" init --bare "$remote_absorbed" >/dev/null
git -C "$remote_absorbed" symbolic-ref HEAD refs/heads/main
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
git add .gitnest .gitignore .gitattributes NEST_README.md src/lib src/nonempty hist/lib
git commit -m "initial outer files" >/dev/null

# --preserve-history needs git-filter-repo; without it, absorb must refuse and
# leave the workspace untouched (no manifest entry, no backup directory).
if ! command -v git-filter-repo >/dev/null 2>&1; then
    if "$GIT_NEST" absorb hist/lib "file://$remote_absorbed" --preserve-history >preserve.out 2>preserve.err; then
        echo "UNEXPECTED RESULT: absorb --preserve-history should fail when git-filter-repo is missing" >&2
        exit 1
    fi
    assert_file_contains preserve.err 'requires git-filter-repo'
    assert_file_not_contains .gitnest '[subproject "hist/lib"]'
    test -z "$(ls -d .gitnest-recovery-* 2>/dev/null)"
fi

# A push target that already has commits must be refused, since git-nest does not
# overwrite non-empty remotes during a files absorb.
if "$GIT_NEST" absorb src/nonempty "file://$remote_nonempty" --push >nonempty.out 2>nonempty.err; then
    echo "UNEXPECTED RESULT: absorb --push should refuse a non-empty remote" >&2
    exit 1
fi
assert_file_contains nonempty.err 'overriding non-empty remotes is deliberately not implemented'
assert_file_not_contains .gitnest '[subproject "src/nonempty"]'

# The happy path: absorb tracked files into a new subproject and push them.
"$GIT_NEST" absorb src/lib "file://$remote_absorbed" --push --message "initial absorbed lib" >absorb.out
test -d src/lib/.git
assert_file_contains .gitnest '[subproject "src/lib"]'
assert_file_contains .gitnest "repo=file://$remote_absorbed"
assert_file_contains .gitignore 'src/lib/'
assert_file_contains absorb.out 'Absorbed src/lib as a git-nest subproject'
git -C src/lib rev-parse --verify main >/dev/null
git --git-dir="$remote_absorbed" rev-parse --verify main >/dev/null
git diff --cached --name-status >absorb_staged.out
assert_file_contains absorb_staged.out 'D	src/lib/one.txt'
assert_file_contains absorb_staged.out 'D	src/lib/two.txt'
assert_file_contains absorb_staged.out 'M	.gitnest'
test -z "$(ls -d .gitnest-recovery-* 2>/dev/null)"

git commit -m "absorb lib" >/dev/null

# inline reverses it: the subproject folds back into ordinary tracked files.
"$GIT_NEST" inline src/lib >inline.out
test ! -e src/lib/.git
assert_file_not_contains .gitnest '[subproject "src/lib"]'
assert_file_not_contains .gitignore 'src/lib/'
assert_file_contains inline.out 'Inlined src/lib into the outer repository'
git diff --cached --name-status >inline_staged.out
assert_file_contains inline_staged.out 'A	src/lib/one.txt'
assert_file_contains inline_staged.out 'A	src/lib/two.txt'
test -z "$(ls -d .gitnest-recovery-* 2>/dev/null)"

# absorb refuses staged outer changes under the path unless forced.
if "$GIT_NEST" absorb src/lib "file://$remote_forced" --dry-run >dirty_staged.out 2>dirty_staged.err; then
    echo "UNEXPECTED RESULT: absorb should refuse staged outer changes without --force" >&2
    exit 1
fi
assert_file_contains dirty_staged.err 'staged outer-repository changes'

git commit -m "inline lib" >/dev/null

# absorb refuses untracked files under the path.
printf 'fresh\n' >src/lib/fresh.txt
if "$GIT_NEST" absorb src/lib "file://$remote_forced" >fresh.out 2>fresh.err; then
    echo "UNEXPECTED RESULT: absorb should refuse untracked files" >&2
    exit 1
fi
assert_file_contains fresh.err 'commit these files in the outer repo first'
rm src/lib/fresh.txt

# absorb refuses unstaged content changes under the path.
printf 'unstaged\n' >>src/lib/one.txt
if "$GIT_NEST" absorb src/lib "file://$remote_forced" >unstaged.out 2>unstaged.err; then
    echo "UNEXPECTED RESULT: absorb should refuse unstaged outer changes" >&2
    exit 1
fi
assert_file_contains unstaged.err 'commit these files in the outer repo first'
git checkout -- src/lib/one.txt

# --force lets absorb replace staged outer state under the path.
printf 'staged override\n' >>src/lib/one.txt
git add src/lib/one.txt
"$GIT_NEST" absorb src/lib "file://$remote_forced" --force --message "forced staged absorb" >force_absorb.out
test -d src/lib/.git
assert_file_contains force_absorb.out 'Absorbed src/lib as a git-nest subproject'
assert_file_contains .gitnest '[subproject "src/lib"]'
test -z "$(ls -d .gitnest-recovery-* 2>/dev/null)"

# A files-source dry-run reports the plan and writes nothing.
"$GIT_NEST" absorb src/nonempty "file://$remote_absorbed" --dry-run >dry.out
assert_file_contains dry.out 'Would absorb outer-repo files src/nonempty'
assert_file_not_contains .gitnest '[subproject "src/nonempty"]'
test -z "$(ls -d .gitnest-recovery-* 2>/dev/null)"

# inline surfaces recovery guidance when the outer commit fails after the backup.
git -C src/lib push -u origin main >/dev/null
mkdir -p .git/hooks
cat >.git/hooks/pre-commit <<'HOOK'
#!/bin/sh
echo "blocking inline commit" >&2
exit 1
HOOK
chmod +x .git/hooks/pre-commit
if "$GIT_NEST" inline src/lib --commit >inline_commit_fail.out 2>inline_commit_fail.err; then
    echo "UNEXPECTED RESULT: inline --commit should surface recovery guidance when commit fails after backup" >&2
    exit 1
fi
assert_file_contains inline_commit_fail.err 'recovery backup is in .gitnest-recovery-inline'
assert_file_contains inline_commit_fail.err 'RECOVERY.txt'
test ! -e src/lib/.git
# The interrupted-conversion recovery backup remains for the user to restore.
test -n "$(ls -d .gitnest-recovery-inline-* 2>/dev/null)"

describe_result "absorb (files) and inline round-trip cleanly and both reject unsafe repository states."
