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
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote" libs/foo >/dev/null
git add .stack .gitignore
git commit -m "initial workspace" >/dev/null

# Basic command and argument validation should produce controlled failures.
if "$GIT_STACK" no-such-command >unknown.out 2>unknown.err; then
    echo "unknown command should fail" >&2
    exit 1
fi
assert_file_contains unknown.err "Error: unknown command"
if "$GIT_STACK" init extra >init_args.out 2>init_args.err; then
    echo "init with extra arguments should fail" >&2
    exit 1
fi
assert_file_contains init_args.err "unknown init option: extra"
if "$GIT_STACK" start >start_args.out 2>start_args.err; then
    echo "start without a branch should fail" >&2
    exit 1
fi
assert_file_contains start_args.err "usage: git-stack start"
if "$GIT_STACK" start XX-1 --unknown >start_option.out 2>start_option.err; then
    echo "unknown start option should fail" >&2
    exit 1
fi
assert_file_contains start_option.err "unknown start option"
if "$GIT_STACK" foreach >foreach_args.out 2>foreach_args.err; then
    echo "foreach without command should fail" >&2
    exit 1
fi
assert_file_contains foreach_args.err "usage: git-stack foreach"
if "$GIT_STACK" install-hooks extra >hook_args.out 2>hook_args.err; then
    echo "install-hooks with arguments should fail" >&2
    exit 1
fi
assert_file_contains hook_args.err "install-hooks takes no arguments"

# Finalize selectors must be complete and mutually exclusive.
if "$GIT_STACK" finalize libs/foo --revision >finalize_missing_value.out 2>finalize_missing_value.err; then
    echo "finalize --revision without value should fail" >&2
    exit 1
fi
assert_file_contains finalize_missing_value.err "--revision requires a value"
if "$GIT_STACK" finalize libs/foo --revision HEAD --tag v1 >finalize_combo.out 2>finalize_combo.err; then
    echo "finalize with multiple selectors should fail" >&2
    exit 1
fi
assert_file_contains finalize_combo.err "finalize selectors are mutually exclusive"
if "$GIT_STACK" finalize libs/missing --revision HEAD >finalize_missing_module.out 2>finalize_missing_module.err; then
    echo "finalize of a missing module should fail" >&2
    exit 1
fi
assert_file_contains finalize_missing_module.err "is not a checked-out module"

# Upload must reject committed work on detached HEAD before recording pending state.
git -C libs/foo checkout --detach >/dev/null
printf 'detached\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "detached work" >/dev/null
if "$GIT_STACK" upload >detached_upload.out 2>detached_upload.err; then
    echo "upload should fail for committed work on detached HEAD" >&2
    exit 1
fi
assert_file_contains detached_upload.err "committed work on detached HEAD"
git -C libs/foo branch detached-test-save HEAD >/dev/null
git -C libs/foo checkout -B no-origin main >/dev/null

# Upload must reject changed modules that cannot push to origin.
git -C libs/foo remote remove origin
printf 'no origin\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "no origin work" >/dev/null
if "$GIT_STACK" upload >no_origin_upload.out 2>no_origin_upload.err; then
    echo "upload should fail when a changed module has no origin" >&2
    exit 1
fi
assert_file_contains no_origin_upload.err "has no origin remote"

# A bad explicit revision should fail clearly and leave the manifest unchanged.
cp .stack manifest.before
if "$GIT_STACK" finalize libs/foo --revision does-not-exist >bad_revision.out 2>bad_revision.err; then
    echo "finalize --revision should fail for a missing commit" >&2
    exit 1
fi
assert_file_contains bad_revision.err "Error: cannot finalize libs/foo with --revision"
cmp .stack manifest.before >/dev/null

# A missing target branch should fail before finalization mutates the manifest.
sed 's/^target_branch=.*/target_branch=missing-target/' .stack >.stack.tmp
mv .stack.tmp .stack
cp .stack manifest.bad-target
if "$GIT_STACK" finalize libs/foo --use-target-head >bad_target.out 2>bad_target.err; then
    echo "finalize --use-target-head should fail for a missing target" >&2
    exit 1
fi
assert_file_contains bad_target.err "Error: cannot resolve target head for libs/foo"
cmp .stack manifest.bad-target >/dev/null

# A malformed module section without repo= should fail instead of writing empty state.
sed '/^repo=/d' .stack >.stack.tmp
mv .stack.tmp .stack
if "$GIT_STACK" refresh >missing_repo.out 2>missing_repo.err; then
    echo "refresh should fail for a manifest module without repo" >&2
    exit 1
fi
assert_file_contains missing_repo.err "Error: module libs/foo is missing repo"
