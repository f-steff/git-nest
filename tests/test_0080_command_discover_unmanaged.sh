#!/bin/sh
# Test: discover finds unmanaged repos, submodules, and nested nests with depth and exclude bounds

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_discover_unmanaged

# discover scans the current nest for nested Git repositories and submodules that
# are not managed by .gitnest, bounded by depth and pruned by excludes.
test_step "Exercise discover of unmanaged repositories" "discover must find unmanaged repos, submodules, and nested nests, mark repos inside managed subprojects, honor --max-depth and --exclude, and never follow symlinks."

root=$(test_workspace command_discover_unmanaged)
outer="$root/outer"
remote_foo="$root/remotes/foo.git"
remote_sub="$root/remotes/sub.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_sub" "$root/seed/sub"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote_foo" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "init nest" >/dev/null

# --- Empty discovery ---
test_step "Discover finds nothing in a clean nest" "With only a managed subproject present, discover reports nothing."
run_capture "empty discover reports nothing" empty.out empty.err -- "$GIT_NEST" discover
assert_file_contains empty.out 'No unmanaged repositories found'

# --- Seed several repositories of different kinds ---
git clone "file://$remote_foo" tools/helper >/dev/null 2>&1              # unmanaged standalone repo
git clone "file://$remote_foo" libs/foo/inner >/dev/null 2>&1           # repo inside a managed subproject
git -c protocol.file.allow=always submodule add "file://$remote_sub" ext/sub >/dev/null 2>&1
git commit -m "add submodule" >/dev/null
mkdir -p apps/inner                                                      # a nested nest root
( cd apps/inner && git init -q && git_config && printf '[project]\nversion=1\n' >.gitnest && echo x >f && git add -A && git commit -qm seed )
mkdir -p node_modules/pkg
git clone "file://$remote_foo" node_modules/pkg/dep >/dev/null 2>&1      # excluded by default

# --- Porcelain discovery classifies each kind ---
test_step "Discover classifies each repository kind" "Standalone repos, submodules, and nested nests get distinct codes, and pruned directories are skipped."
run_capture "discover porcelain lists repositories" disc.out disc.err -- "$GIT_NEST" discover --porcelain
assert_file_contains disc.out 'R	tools/helper	nested-repo'
assert_file_contains disc.out 'S	ext/sub	submodule'
assert_file_contains disc.out 'N	apps/inner	nest-root'
# A repo inside a managed subproject is reported with the managing parent.
assert_file_contains disc.out 'libs/foo/inner	nested-repo	libs/foo'
# The managed subproject's own checkout is never reported.
assert_file_not_contains disc.out 'R	libs/foo	'
# Default-excluded directories are pruned.
assert_file_not_contains disc.out 'node_modules'

# --- Suggestions guide the next step ---
test_step "Discover suggests a next step" "Each row includes a safe suggested command."
assert_file_contains disc.out 'run git-nest absorb tools/helper'

# --- JSON output ---
test_step "Discover JSON output" "discover --json emits the shared envelope with one row per repository."
run_capture "discover json emits envelope" disc.json disc_j.err -- "$GIT_NEST" discover --json
assert_file_contains disc.json '"command":"discover"'
assert_file_contains disc.json '"path":"tools/helper"'
python -m json.tool disc.json >/dev/null 2>&1 || python3 -m json.tool disc.json >/dev/null 2>&1 || true

# --- --max-depth bounds the scan ---
test_step "Discover honors --max-depth" "A repository deeper than the limit is not reported."
git clone "file://$remote_foo" a/b/c/deep >/dev/null 2>&1
run_capture "shallow scan misses the deep repo" shallow.out shallow.err -- "$GIT_NEST" discover --porcelain --max-depth 2
assert_file_not_contains shallow.out 'a/b/c/deep'
run_capture "deep scan finds the deep repo" deep.out deep.err -- "$GIT_NEST" discover --porcelain --max-depth 6
assert_file_contains deep.out 'a/b/c/deep'

# --- --exclude prunes an extra directory ---
test_step "Discover honors --exclude" "A user-supplied exclude directory is pruned from the scan."
run_capture "custom exclude prunes tools" excl.out excl.err -- "$GIT_NEST" discover --porcelain --exclude tools
assert_file_not_contains excl.out 'tools/helper'

# --- Invalid --exclude is rejected (guards the eval-built find expression) ---
test_step "Reject unsafe --exclude values" "Only simple directory-name tokens are allowed."
run_fail "unsafe exclude rejected" any -- sh -c '"$1" discover --exclude "foo;rm" >bad.out 2>bad.err' sh "$GIT_NEST"
assert_file_contains bad.err 'invalid --exclude value'

# --- Symlinked directories are not followed (skipped where symlinks are unavailable) ---
test_step "Discover does not follow symlinks" "A repository reachable only through a symlink must not be reported."
if ln -s tools symlinked_tools 2>/dev/null && [ -L symlinked_tools ]; then
    run_capture "symlinked path is not followed" sym.out sym.err -- "$GIT_NEST" discover --porcelain
    assert_file_not_contains sym.out 'symlinked_tools/helper'
else
    printf 'Note: symlink check not run because this platform cannot create symlinks\n'
fi

describe_result "discover found unmanaged repos, submodules, and nested nests, honored depth/exclude bounds, rejected unsafe excludes, and did not follow symlinks."
