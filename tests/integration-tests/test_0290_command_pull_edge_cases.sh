#!/bin/sh
# Test: pull handles detached HEAD, no upstream, diverged, dirty, --sure, --recursive, --dry-run, --json, and network failures

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_pull_edge_cases

# pull fast-forwards clean, tracked subprojects to their upstream branch head
# and snapshots the result. Every subproject outcome must be reported by
# path with a concrete fix-it suggestion, not just a count.
test_step "Exercise pull across every subproject outcome" "pull must fast-forward a clean, tracked subproject; skip and report dirty, detached-HEAD, and no-upstream subprojects by path with a fix-it command; report (never force) a diverged subproject; continue past a network failure; and support --sure, --recursive, --dry-run, and --json."

root=$(test_workspace command_pull_edge_cases)
outer="$root/outer"
remote_ff="$root/remotes/ff.git"
remote_div="$root/remotes/div.git"
remote_detached="$root/remotes/detached.git"
remote_noup="$root/remotes/noup.git"
remote_dirty="$root/remotes/dirty.git"
remote_netfail="$root/remotes/netfail.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_ff" "$root/seed/ff"
make_bare_remote "$remote_div" "$root/seed/div"
make_bare_remote "$remote_detached" "$root/seed/detached"
make_bare_remote "$remote_noup" "$root/seed/noup"
make_bare_remote "$remote_dirty" "$root/seed/dirty"
make_bare_remote "$remote_netfail" "$root/seed/netfail"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote_ff" libs/ff >/dev/null
"$GIT_NEST" add "file://$remote_div" libs/div >/dev/null
"$GIT_NEST" add "file://$remote_detached" libs/detached >/dev/null
"$GIT_NEST" add "file://$remote_noup" libs/noup >/dev/null
"$GIT_NEST" add "file://$remote_dirty" libs/dirty >/dev/null
"$GIT_NEST" add "file://$remote_netfail" libs/netfail >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "init nest" >/dev/null

# --- libs/ff: remote gets a new commit; a plain pull must fast-forward it ---
(
    cd "$root/seed/ff"
    printf 'more\n' >>file.txt
    git add -A && git commit -qm "advance ff" && git push -q origin main
)

# --- libs/div: both sides advance independently from the same base, so
# fast-forward is impossible ---
(
    cd "$root/seed/div"
    printf 'remote-side\n' >>file.txt
    git add -A && git commit -qm "advance div remotely" && git push -q origin main
)
(cd libs/div && printf 'local-side\n' >>file.txt && git add -A && git commit -qm "advance div locally")

# --- libs/detached: detach HEAD from its branch ---
(cd libs/detached && git checkout -q --detach HEAD)

# --- libs/noup: drop upstream tracking ---
(cd libs/noup && git branch --unset-upstream)

# --- libs/dirty: leave an uncommitted change ---
printf 'dirty\n' >>libs/dirty/file.txt

# --- libs/netfail: point origin at a remote that no longer exists, to
# simulate a network/fetch failure ---
(cd libs/netfail && git remote set-url origin "$root/remotes/does-not-exist.git")

# --- Dry-run reports the plan without fetching or writing ---
test_step "pull --dry-run reports the plan without writing" "No fetch, no merge, no snapshot; only a per-subproject preview line."
run_capture "dry-run previews without writing" dry.out dry.err -- "$GIT_NEST" pull --dry-run
assert_file_contains dry.out '[dry-run] would pull libs/ff:'
assert_file_contains dry.out '  Pulled:        0'
git -C libs/ff rev-parse HEAD >ff_before.txt

# --- Actual pull: ff fast-forwards; dirty/detached/noup are skipped with
# fix-it commands; div is reported diverged, never forced; netfail is
# reported failed and does not stop the rest. The command exits nonzero
# because libs/div diverged and libs/netfail failed. ---
test_step "pull fast-forwards the clean tracked subproject and reports every other outcome by path" "Each category must list the actual subproject path with a concrete, safely quoted fix-it command, and the command must exit nonzero when any subproject failed or diverged."
set +e
"$GIT_NEST" pull >run.out 2>run.err
pull_rc=$?
set -e
[ "$pull_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: pull must exit nonzero when a subproject diverged or failed, got 0\n' >&2
    exit 1
}
assert_file_contains run.out 'Pulled libs/ff to'
assert_file_contains run.out '  Pulled:        1'
assert_file_contains run.out 'Skipped (dirty):'
assert_file_contains run.out 'libs/dirty (commit or stash changes first)'
assert_file_contains run.out 'Skipped (detached HEAD):'
assert_file_contains run.out "run: git -C libs/detached checkout <branch>"
assert_file_contains run.out 'Skipped (no upstream tracking):'
assert_file_contains run.out "run: git -C libs/noup branch --set-upstream-to=origin/"
assert_file_contains run.out 'Diverged (not fast-forward):'
assert_file_contains run.out "run: git -C libs/div merge origin/<branch> or git -C libs/div rebase origin/<branch>"
assert_file_contains run.out 'Failed:'
assert_file_contains run.out 'libs/netfail (check network/remote access, then retry)'

# --- libs/ff actually advanced; libs/div was never force-updated ---
ff_after=$(git -C libs/ff rev-parse HEAD)
ff_before=$(cat ff_before.txt)
[ "$ff_after" != "$ff_before" ] || {
    printf 'UNEXPECTED RESULT: libs/ff did not advance after pull\n' >&2
    exit 1
}
div_head=$(git -C libs/div log -1 --format=%s)
[ "$div_head" = "advance div locally" ] || {
    printf 'UNEXPECTED RESULT: libs/div was changed by pull despite being diverged\n' >&2
    exit 1
}

# --- The manifest was snapshotted for the pulled subproject only ---
assert_file_contains .gitnest "revision=$ff_after"

# --- JSON output for a subsequent, already-up-to-date run ---
# (libs/div still diverged and libs/netfail still fails, so pull keeps
# exiting nonzero; the JSON envelope is what matters here.)
test_step "pull --json emits machine-readable output" "A second run (ff already up to date) must still emit the shared envelope."
set +e
"$GIT_NEST" pull --json >run.json 2>run.json.err
json_rc=$?
set -e
assert_file_contains run.json '"command":"pull"'
[ "$json_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: pull --json must exit nonzero while libs/div and libs/netfail are broken, got 0\n' >&2
    exit 1
}

# --- --sure also pulls the nest root ---
test_step "pull --sure also pulls the nest root" "Without --sure the root is left alone; with it, the root's own remote is fetched and fast-forwarded."
root_remote="$root/remotes/root.git"
git init --bare -q "$root_remote"
git remote add origin "$root_remote"
git push -q -u origin HEAD:main
# Point the bare remote's symbolic HEAD at main so that a bare clone
# checks out main instead of whatever the git default branch name is
# (older git and some configurations default to "master").
git --git-dir="$root_remote" symbolic-ref HEAD refs/heads/main
# Use -b main so the clone checks out main even if the remote HEAD
# points elsewhere (robust across all git versions).
git clone -q -b main "$root_remote" "$root/root-mirror" >/dev/null 2>&1
(cd "$root/root-mirror" && git_config && echo marker >root_marker.txt && git add -A && git commit -qm "advance root remotely" && git push -q origin main)
set +e
"$GIT_NEST" pull >nosure.out 2>nosure.err
nosure_rc=$?
set -e
[ "$nosure_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: pull must exit nonzero while libs/div and libs/netfail are broken, got 0\n' >&2
    exit 1
}
test ! -f root_marker.txt
set +e
"$GIT_NEST" pull --sure >sure.out 2>sure.err
sure_rc=$?
set -e
[ "$sure_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: pull --sure must exit nonzero while libs/div and libs/netfail are broken, got 0\n' >&2
    exit 1
}
test -f root_marker.txt

# --- --recursive pulls into nested nests ---
test_step "pull --recursive descends into nested nests" "A nested nest's own subproject must also be fast-forwarded when --recursive is given, and left alone without it."
remote_nested="$root/remotes/nested.git"
make_bare_remote "$remote_nested" "$root/seed/nested"
mkdir -p nested
(cd nested && git init -q && git_config && echo seed >f.txt && git add -A && git commit -qm seed)
"$GIT_NEST" absorb nested "file://$remote_nested" >/dev/null
(cd nested && "$GIT_NEST" init --sure >/dev/null && "$GIT_NEST" add "file://$remote_ff" inner-ff >/dev/null && git add .gitnest .gitignore .gitattributes NEST_README.md && git commit -qm "nested nest init")
(
    cd "$root/seed/ff"
    printf 'even-more\n' >>file.txt
    git add -A && git commit -qm "advance ff again" && git push -q origin main
)
inner_before=$(git -C nested/inner-ff rev-parse HEAD)
set +e
"$GIT_NEST" pull >norec.out 2>norec.err
norec_rc=$?
set -e
[ "$norec_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: plain pull must exit nonzero while libs/div and libs/netfail are broken, got 0\n' >&2
    exit 1
}
inner_after_norec=$(git -C nested/inner-ff rev-parse HEAD)
[ "$inner_before" = "$inner_after_norec" ] || {
    printf 'UNEXPECTED RESULT: nested nest subproject changed without --recursive\n' >&2
    exit 1
}
set +e
"$GIT_NEST" pull --recursive >rec.out 2>rec.err
rec_rc=$?
set -e
[ "$rec_rc" -ne 0 ] || {
    printf 'UNEXPECTED RESULT: pull --recursive must exit nonzero while libs/div and libs/netfail are broken, got 0\n' >&2
    exit 1
}
assert_file_contains rec.out 'Pulling project:'
inner_after_rec=$(git -C nested/inner-ff rev-parse HEAD)
[ "$inner_before" != "$inner_after_rec" ] || {
    printf 'UNEXPECTED RESULT: pull --recursive did not advance the nested nest subproject\n' >&2
    exit 1
}

describe_result "pull fast-forwarded the clean tracked subproject, reported dirty/detached/no-upstream/diverged/failed subprojects by path with fix-it commands, never forced a diverged merge, and correctly supported --dry-run, --json, --sure, and --recursive."
