#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin graceful_failures

work=$(test_workspace graceful_failures)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

# Build a simple workspace and then corrupt inputs to verify graceful failures.
mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

# Basic command and argument validation should produce controlled failures.
if "$GIT_LEGO" no-such-command >unknown.out 2>unknown.err; then
    echo "unknown command should fail" >&2
    exit 1
fi
assert_file_contains unknown.err "Error: unknown command"
if "$GIT_LEGO" init extra >init_args.out 2>init_args.err; then
    echo "init with extra arguments should fail" >&2
    exit 1
fi
assert_file_contains init_args.err "unknown init option: extra"
if "$GIT_LEGO" start >start_args.out 2>start_args.err; then
    echo "start without a branch should fail" >&2
    exit 1
fi
assert_file_contains start_args.err "usage: git-lego start"
if "$GIT_LEGO" start XX-1 --unknown >start_option.out 2>start_option.err; then
    echo "unknown start option should fail" >&2
    exit 1
fi
assert_file_contains start_option.err "unknown start option"
if "$GIT_LEGO" foreach >foreach_args.out 2>foreach_args.err; then
    echo "foreach without command should fail" >&2
    exit 1
fi
assert_file_contains foreach_args.err "usage: git-lego foreach"
if "$GIT_LEGO" install-hooks extra >hook_args.out 2>hook_args.err; then
    echo "install-hooks with arguments should fail" >&2
    exit 1
fi
assert_file_contains hook_args.err "install-hooks takes no arguments"
if "$GIT_LEGO" refresh >old_refresh.out 2>old_refresh.err; then
    echo "old refresh command should fail" >&2
    exit 1
fi
assert_file_contains old_refresh.err "unknown command: refresh; use snapshot"
if "$GIT_LEGO" available >old_available.out 2>old_available.err; then
    echo "old available command should fail" >&2
    exit 1
fi
assert_file_contains old_available.err "unknown command: available; use outdated"
if "$GIT_LEGO" check >old_check.out 2>old_check.err; then
    echo "old check command should fail" >&2
    exit 1
fi
assert_file_contains old_check.err "unknown command: check; use no-pending"
if "$GIT_LEGO" foreach-modified >foreach_modified_args.out 2>foreach_modified_args.err; then
    echo "foreach-modified without command or machine output should fail" >&2
    exit 1
fi
assert_file_contains foreach_modified_args.err "usage: git-lego foreach-modified"

legacy="$work/legacy"
make_repo "$legacy"
printf '[stack]\n' >"$legacy/.stack"
cd "$legacy"
if "$GIT_LEGO" status >legacy_stack.out 2>legacy_stack.err; then
    echo "legacy .stack manifest should fail" >&2
    exit 1
fi
assert_file_contains legacy_stack.err "legacy .stack manifest found"
cd "$outer"

# Finalize selectors must be complete and mutually exclusive.
if "$GIT_LEGO" finalize libs/foo --revision >finalize_missing_value.out 2>finalize_missing_value.err; then
    echo "finalize --revision without value should fail" >&2
    exit 1
fi
assert_file_contains finalize_missing_value.err "--revision requires a value"
if "$GIT_LEGO" finalize libs/foo --revision HEAD --tag v1 >finalize_combo.out 2>finalize_combo.err; then
    echo "finalize with multiple selectors should fail" >&2
    exit 1
fi
assert_file_contains finalize_combo.err "finalize selectors are mutually exclusive"
if "$GIT_LEGO" finalize libs/missing --revision HEAD >finalize_missing_subproject.out 2>finalize_missing_subproject.err; then
    echo "finalize of a missing subproject should fail" >&2
    exit 1
fi
assert_file_contains finalize_missing_subproject.err "is not a checked-out subproject"

# Upload must reject committed work on detached HEAD before recording pending state.
git -C libs/foo checkout --detach >/dev/null
printf 'detached\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "detached work" >/dev/null
if "$GIT_LEGO" upload >detached_upload.out 2>detached_upload.err; then
    echo "upload should fail for committed work on detached HEAD" >&2
    exit 1
fi
assert_file_contains detached_upload.err "committed work on detached HEAD"
git -C libs/foo branch detached-test-save HEAD >/dev/null
git -C libs/foo checkout -B no-origin main >/dev/null

# Upload must reject changed subprojects that cannot push to origin.
git -C libs/foo remote remove origin
printf 'no origin\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "no origin work" >/dev/null
if "$GIT_LEGO" upload >no_origin_upload.out 2>no_origin_upload.err; then
    echo "upload should fail when a changed subproject has no origin" >&2
    exit 1
fi
assert_file_contains no_origin_upload.err "has no origin remote"

# A bad explicit revision should fail clearly and leave the manifest unchanged.
cp .gitlego manifest.before
if "$GIT_LEGO" finalize libs/foo --revision does-not-exist >bad_revision.out 2>bad_revision.err; then
    echo "finalize --revision should fail for a missing commit" >&2
    exit 1
fi
assert_file_contains bad_revision.err "Error: cannot finalize libs/foo with --revision"
cmp .gitlego manifest.before >/dev/null

# A missing target branch should fail before finalization mutates the manifest.
sed 's/^target_branch=.*/target_branch=missing-target/' .gitlego >.gitlego.tmp
mv .gitlego.tmp .gitlego
cp .gitlego manifest.bad-target
if "$GIT_LEGO" finalize libs/foo --use-target-head >bad_target.out 2>bad_target.err; then
    echo "finalize --use-target-head should fail for a missing target" >&2
    exit 1
fi
assert_file_contains bad_target.err "Error: cannot resolve target head for libs/foo"
cmp .gitlego manifest.bad-target >/dev/null

# A malformed subproject section without repo= should fail instead of writing empty state.
sed '/^repo=/d' .gitlego >.gitlego.tmp
mv .gitlego.tmp .gitlego
if "$GIT_LEGO" snapshot >missing_repo.out 2>missing_repo.err; then
    echo "snapshot should fail for a manifest subproject without repo" >&2
    exit 1
fi
assert_file_contains missing_repo.err "Error: subproject libs/foo is missing repo"
