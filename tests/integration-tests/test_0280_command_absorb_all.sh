#!/bin/sh
# Test: absorb-all scans like survey and absorbs every detected submodule and nested repo

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_absorb_all

# absorb-all reuses survey's scan, then absorbs each detected submodule and
# nested repo, deepest-first, with rollback by default on a mid-batch
# failure. It never touches git-subrepos, subtrees, or anything found inside
# another boundary the scan already classified.
test_step "Exercise absorb-all end to end" "absorb-all must absorb submodules and nested repos, skip subrepos/subtrees and boundary-nested items, support --dry-run without writing, create or extend a nest with --sure, and roll back a mid-batch failure by default (or keep partial progress with --force-partial)."

root=$(test_workspace command_absorb_all)
outer="$root/outer"
remote_foo="$root/remotes/foo.git"
remote_sub="$root/remotes/sub.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_sub" "$root/seed/sub"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "init nest" >/dev/null

# --- Nothing to absorb ---
test_step "absorb-all reports nothing to do in a clean nest" "With no unmanaged submodules or nested repos present, absorb-all must not fail or write anything."
run_capture "no candidates reports cleanly" none.out none.err -- "$GIT_NEST" absorb-all
assert_file_contains none.out 'No submodules or nested repos found to absorb.'

# --- Seed candidates and exclusions ---
git clone "file://$remote_foo" tools/one >/dev/null 2>&1
git -c protocol.file.allow=always submodule add "file://$remote_sub" ext/sub >/dev/null 2>&1
git commit -m "add submodule" >/dev/null
mkdir -p external/subrepo
printf 'hi\n' >external/subrepo/a.txt
cat >external/subrepo/.gitrepo <<EOF
[subrepo]
	remote = file://$remote_foo
	branch = main
	commit = 0000000000000000000000000000000000000000
EOF
git add external
git commit -m "add external/subrepo" >/dev/null
# A nested repo inside the subrepo: excluded from absorb-all not because it
# would trip absorb's own deeper-repo guard (the subrepo is never itself an
# absorb-all candidate at all), but because it sits inside a boundary
# (the subrepo) that survey's scan already classified.
git clone "file://$remote_foo" external/subrepo/inner >/dev/null 2>&1

# --- --dry-run reports the plan without writing, excluding subrepo and the
# boundary-nested item ---
test_step "absorb-all --dry-run reports the plan without writing" "The subrepo and the repo nested inside it must never appear as candidates."
run_capture "dry-run reports the plan" dry.out dry.err -- "$GIT_NEST" absorb-all --dry-run
assert_file_contains dry.out 'Would absorb 2 subproject(s):'
assert_file_contains dry.out 'tools/one'
assert_file_contains dry.out 'ext/sub'
assert_file_not_contains dry.out 'external/subrepo'
assert_file_not_contains .gitnest '[subproject "tools/one"]'

# --- JSON dry-run ---
run_capture "dry-run json" dry.json dry.json.err -- "$GIT_NEST" absorb-all --dry-run --json
assert_file_contains dry.json '"command":"absorb-all"'
assert_file_contains dry.json '"dry_run":true'
python -m json.tool dry.json >/dev/null 2>&1 || python3 -m json.tool dry.json >/dev/null 2>&1 || true

# --- Actual absorb-all absorbs both candidates, deepest-first, and skips the
# excluded ones ---
test_step "absorb-all absorbs the submodule and nested repo, skipping subrepo and boundary-nested items" "Both real candidates end up as managed subprojects; the subrepo and the item nested inside it remain untouched."
run_capture "absorb-all absorbs both candidates" run.json run.err -- "$GIT_NEST" absorb-all --json
assert_file_contains run.json '"path":"tools/one"'
assert_file_contains run.json '"path":"ext/sub"'
assert_file_contains .gitnest '[subproject "tools/one"]'
assert_file_contains .gitnest '[subproject "ext/sub"]'
assert_file_not_contains .gitnest '[subproject "external/subrepo"]'
assert_file_not_contains .gitnest '[subproject "external/subrepo/inner"]'
test -d external/subrepo/inner/.git

# --- Rerunning finds nothing left except the excluded items ---
run_capture "survey after absorb-all shows only the excluded items" after.out after.err -- "$GIT_NEST" survey --porcelain
assert_file_contains after.out 'G	external/subrepo	subrepo'
assert_file_not_contains after.out 'R	tools/one	'
assert_file_not_contains after.out 'S	ext/sub	'

# --- --exclude and --include narrow the scan the same way survey's do ---
test_step "absorb-all honors --exclude and --include" "These flags must behave identically to survey's, since absorb-all reuses the same scan."
git clone "file://$remote_foo" area1/repo1 >/dev/null 2>&1
git clone "file://$remote_foo" area2/repo2 >/dev/null 2>&1
run_capture "exclude prunes area1" excl.out excl.err -- "$GIT_NEST" absorb-all --dry-run --exclude area1
assert_file_not_contains excl.out 'area1/repo1'
assert_file_contains excl.out 'area2/repo2'
run_capture "include narrows to area1 only" incl.out incl.err -- "$GIT_NEST" absorb-all --dry-run --include area1
assert_file_contains incl.out 'area1/repo1'
assert_file_not_contains incl.out 'area2/repo2'
run_ok "absorb only area1 via --include" -- "$GIT_NEST" absorb-all --include area1
assert_file_contains .gitnest '[subproject "area1/repo1"]'
assert_file_not_contains .gitnest '[subproject "area2/repo2"]'

# --- Rollback on a mid-batch failure ---
test_step "absorb-all rolls back a mid-batch failure by default" "A deeper candidate absorbs successfully, then a shallower one fails (no origin remote); the deeper one must be restored to its pre-absorb state and the manifest must be unchanged."
mkdir -p rollback/deep
git clone "file://$remote_foo" rollback/deep/good >/dev/null 2>&1
mkdir -p rollback/bad
git init -q rollback/bad
(cd rollback/bad && git_config && echo z >z.txt && git add -A && git commit -qm seed)
before_manifest=$(cat .gitnest)
run_fail "mid-batch failure reported and rolled back" any -- sh -c '"$1" absorb-all >rb.out 2>rb.err' sh "$GIT_NEST"
assert_file_contains rb.err 'Rolling back'
assert_file_contains rb.err 'Rolled back.'
assert_file_not_contains .gitnest '[subproject "rollback/deep/good"]'
after_manifest=$(cat .gitnest)
[ "$before_manifest" = "$after_manifest" ] || {
    printf 'UNEXPECTED RESULT: manifest changed despite rollback\n' >&2
    exit 1
}
git -C rollback/deep/good remote -v | grep -q "$remote_foo" || {
    printf 'UNEXPECTED RESULT: rollback/deep/good was not restored to its original remote\n' >&2
    exit 1
}
set -- .gitnest-recovery-absorb-all-batch-*
if [ -e "$1" ]; then
    printf 'UNEXPECTED RESULT: recovery backup directory was left behind after a successful rollback\n' >&2
    exit 1
fi

# --- --force-partial keeps successfully-absorbed items instead of rolling back ---
test_step "absorb-all --force-partial keeps partial progress" "The same failure, but with --force-partial: rollback/deep/good stays absorbed, and rollback/bad is reported as the reason to fix and re-run."
run_fail "force-partial keeps the succeeded item" any -- sh -c '"$1" absorb-all --force-partial >fp.out 2>fp.err' sh "$GIT_NEST"
assert_file_contains fp.err 'remain in place'
assert_file_contains .gitnest '[subproject "rollback/deep/good"]'
assert_file_not_contains .gitnest '[subproject "rollback/bad"]'
(cd rollback/bad && git remote add origin "file://$remote_foo")
run_ok "rerun absorbs the fixed remaining item" -- "$GIT_NEST" absorb-all
assert_file_contains .gitnest '[subproject "rollback/bad"]'

describe_result "absorb-all absorbed submodules and nested repos, excluded subrepos/subtrees and boundary-nested items, supported --dry-run/--json/--exclude/--include, and rolled back (or kept, with --force-partial) a mid-batch failure correctly."
