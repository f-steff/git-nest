#!/bin/sh
# Test: survey finds unmanaged repos, submodules, subrepos, and nested nests with depth/exclude/include bounds

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_survey_unmanaged

# survey scans the current nest for nested Git repositories, submodules, and
# git-subrepos that are not managed by .gitnest, bounded by depth and pruned by
# excludes (or narrowed by includes). It replaces the former discover command
# and never adds, syncs, or registers anything.
test_step "Exercise survey of unmanaged repositories" "survey must find unmanaged repos, submodules, subrepos, and nested nests, mark repos inside managed subprojects, honor --max-depth/--exclude/--include, and never follow symlinks."

root=$(test_workspace command_survey_unmanaged)
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
test_step "Survey finds nothing in a clean nest" "With only a managed subproject present, survey reports nothing."
run_capture "empty survey reports nothing" empty.out empty.err -- "$GIT_NEST" survey
assert_file_contains empty.out 'No unmanaged repositories found'

# --- discover is retired and points at survey ---
test_step "discover is retired in favor of survey" "The old command name must fail with migration guidance instead of silently doing nothing or being reinterpreted."
run_fail "discover rejected with migration guidance" any -- sh -c '"$1" discover >disc_old.out 2>disc_old.err' sh "$GIT_NEST"
assert_file_contains disc_old.err 'use git-nest survey'

# --- Seed several repositories of different kinds ---
git clone "file://$remote_foo" tools/helper >/dev/null 2>&1               # unmanaged standalone repo
git clone "file://$remote_foo" libs/foo/inner >/dev/null 2>&1            # repo inside a managed subproject
git -c protocol.file.allow=always submodule add "file://$remote_sub" ext/sub >/dev/null 2>&1
git commit -m "add submodule" >/dev/null
mkdir -p apps/inner                                                       # a nested nest root
(cd apps/inner && git init -q && git_config && printf '[project]\nversion=1\n' >.gitnest && echo x >f && git add -A && git commit -qm seed)
mkdir -p node_modules/pkg
git clone "file://$remote_foo" node_modules/pkg/dep >/dev/null 2>&1       # excluded by default
mkdir -p external/thing
printf 'hi\n' >external/thing/a.txt
cat >external/thing/.gitrepo <<EOF
[subrepo]
	remote = file://$remote_foo
	branch = main
	commit = 0000000000000000000000000000000000000000
EOF
git add external
git commit -m "add external/thing subrepo" >/dev/null

# --- Porcelain discovery classifies each kind, including the new G code ---
test_step "Survey classifies each repository kind" "Standalone repos, submodules, subrepos, and nested nests get distinct codes, and pruned directories are skipped."
run_capture "survey porcelain lists repositories" disc.out disc.err -- "$GIT_NEST" survey --porcelain
assert_file_contains disc.out 'R	tools/helper	nested-repo'
assert_file_contains disc.out 'S	ext/sub	submodule'
assert_file_contains disc.out 'N	apps/inner	nest-root'
assert_file_contains disc.out 'G	external/thing	subrepo'
# A repo inside a managed subproject is reported with the managing parent.
assert_file_contains disc.out 'libs/foo/inner	nested-repo	libs/foo'
# The managed subproject's own checkout is never reported.
assert_file_not_contains disc.out 'R	libs/foo	'
# Default-excluded directories are pruned.
assert_file_not_contains disc.out 'node_modules'

# --- Suggestions guide the next step, and the subrepo suggestion notes the
# absorb-all exclusion ---
test_step "Survey suggests a next step" "Each row includes a safe suggested command; a subrepo's suggestion notes that absorb-all never absorbs it."
assert_file_contains disc.out 'run git-nest absorb tools/helper'
assert_file_contains disc.out 'run git-nest absorb --subrepo external/thing (not absorbed by absorb-all)'

# --- Boundary enforcement: a repo found inside another *unmanaged, freshly
# discovered* item (not yet a managed subproject) must not be reported as an
# independent finding; only the outer boundary is visible on its own. ---
test_step "Survey does not separately report a repo inside another discovered boundary" "Once tools/helper itself is classified, anything found underneath it belongs to that boundary, not to the outer nest's own findings."
git clone "file://$remote_foo" tools/helper/inner >/dev/null 2>&1
run_capture "nested-inside-unmanaged repo is not reported as independent" nestedunmanaged.out nestedunmanaged.err -- "$GIT_NEST" survey --porcelain
assert_file_contains nestedunmanaged.out 'tools/helper/inner	nested-repo	tools/helper'
assert_file_contains nestedunmanaged.out 'inside tools/helper (listed above); resolve that first, then re-run survey to see what is inside it'
assert_file_not_contains nestedunmanaged.out 'inside managed subproject tools/helper'
rm -rf tools/helper/inner

# --- JSON output ---
test_step "Survey JSON output" "survey --json emits the shared envelope with one row per repository."
run_capture "survey json emits envelope" disc.json disc_j.err -- "$GIT_NEST" survey --json
assert_file_contains disc.json '"command":"survey"'
assert_file_contains disc.json '"path":"tools/helper"'
assert_file_contains disc.json '"code":"G"'
python -m json.tool disc.json >/dev/null 2>&1 || python3 -m json.tool disc.json >/dev/null 2>&1 || true

# --- --max-depth bounds the scan ---
test_step "Survey honors --max-depth" "A repository deeper than the limit is not reported."
git clone "file://$remote_foo" a/b/c/deep >/dev/null 2>&1
run_capture "shallow scan misses the deep repo" shallow.out shallow.err -- "$GIT_NEST" survey --porcelain --max-depth 2
assert_file_not_contains shallow.out 'a/b/c/deep'
run_capture "deep scan finds the deep repo" deep.out deep.err -- "$GIT_NEST" survey --porcelain --max-depth 6
assert_file_contains deep.out 'a/b/c/deep'

# --- --exclude prunes an extra directory ---
test_step "Survey honors --exclude" "A user-supplied exclude directory is pruned from the scan."
run_capture "custom exclude prunes tools" excl.out excl.err -- "$GIT_NEST" survey --porcelain --exclude tools
assert_file_not_contains excl.out 'tools/helper'

# --- --include narrows the scan to specific paths ---
test_step "Survey honors --include" "Only the given paths (and their subtrees) are scanned; everything else is skipped, and multiple --include paths are repeatable and additive."
run_capture "single include narrows the scan" inc.out inc.err -- "$GIT_NEST" survey --porcelain --include external
assert_file_contains inc.out 'external/thing'
assert_file_not_contains inc.out 'tools/helper'
assert_file_not_contains inc.out 'ext/sub'
run_capture "repeated include is additive" inc2.out inc2.err -- "$GIT_NEST" survey --porcelain --include external --include tools
assert_file_contains inc2.out 'external/thing'
assert_file_contains inc2.out 'tools/helper'
assert_file_not_contains inc2.out 'ext/sub'
run_fail "include path that does not exist is refused" any -- sh -c '"$1" survey --include does/not/exist >incbad.out 2>incbad.err' sh "$GIT_NEST"
assert_file_contains incbad.err 'does/not/exist'

# --- Invalid --exclude is rejected (guards the eval-built find expression) ---
test_step "Reject unsafe --exclude values" "Only simple directory-name tokens are allowed."
run_fail "unsafe exclude rejected" any -- sh -c '"$1" survey --exclude "foo;rm" >bad.out 2>bad.err' sh "$GIT_NEST"
assert_file_contains bad.err 'invalid --exclude value'

# --- Symlinked directories are not followed (skipped where symlinks are unavailable) ---
test_step "Survey does not follow symlinks" "A repository reachable only through a symlink must not be reported."
if ln -s tools symlinked_tools 2>/dev/null && [ -L symlinked_tools ]; then
    run_capture "symlinked path is not followed" sym.out sym.err -- "$GIT_NEST" survey --porcelain
    assert_file_not_contains sym.out 'symlinked_tools/helper'
else
    printf 'Note: symlink check not run because this platform cannot create symlinks\n'
fi

describe_result "survey found unmanaged repos, submodules, subrepos, and nested nests, honored depth/exclude/include bounds, enforced boundary reporting, rejected unsafe excludes, did not follow symlinks, and confirmed discover is retired."
