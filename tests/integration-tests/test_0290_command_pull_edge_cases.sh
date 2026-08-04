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
git add .gitnest .gitignore .gitattributes
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
# reported failed and does not stop the rest ---
test_step "pull fast-forwards the clean tracked subproject and reports every other outcome by path" "Each category must list the actual subproject path with a concrete, safely quoted fix-it command."
run_capture "pull reports every outcome" run.out run.err -- "$GIT_NEST" pull
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
test_step "pull --json emits machine-readable output" "A second run (ff already up to date) must still succeed and emit the shared envelope."
run_capture "pull json succeeds" run.json run.json.err -- "$GIT_NEST" pull --json
assert_file_contains run.json '"command":"pull"'

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
run_capture "pull without --sure leaves the root alone" nosure.out nosure.err -- "$GIT_NEST" pull
test ! -f root_marker.txt
run_capture "pull --sure pulls the root too" sure.out sure.err -- "$GIT_NEST" pull --sure
test -f root_marker.txt

# --- --recursive pulls into nested nests ---
test_step "pull --recursive descends into nested nests" "A nested nest's own subproject must also be fast-forwarded when --recursive is given, and left alone without it."
remote_nested="$root/remotes/nested.git"
make_bare_remote "$remote_nested" "$root/seed/nested"
mkdir -p nested
(cd nested && git init -q && git_config && echo seed >f.txt && git add -A && git commit -qm seed)
"$GIT_NEST" absorb nested "file://$remote_nested" >/dev/null
(cd nested && "$GIT_NEST" init --sure >/dev/null && "$GIT_NEST" add "file://$remote_ff" inner-ff >/dev/null && git add .gitnest .gitignore .gitattributes && git commit -qm "nested nest init")
(
    cd "$root/seed/ff"
    printf 'even-more\n' >>file.txt
    git add -A && git commit -qm "advance ff again" && git push -q origin main
)
inner_before=$(git -C nested/inner-ff rev-parse HEAD)
run_capture "plain pull does not descend into the nested nest" norec.out norec.err -- "$GIT_NEST" pull
inner_after_norec=$(git -C nested/inner-ff rev-parse HEAD)
[ "$inner_before" = "$inner_after_norec" ] || {
    printf 'UNEXPECTED RESULT: nested nest subproject changed without --recursive\n' >&2
    exit 1
}
run_capture "pull --recursive descends into the nested nest" rec.out rec.err -- "$GIT_NEST" pull --recursive
assert_file_contains rec.out 'Pulling project:'
inner_after_rec=$(git -C nested/inner-ff rev-parse HEAD)
[ "$inner_before" != "$inner_after_rec" ] || {
    printf 'UNEXPECTED RESULT: pull --recursive did not advance the nested nest subproject\n' >&2
    exit 1
}

describe_result "pull fast-forwarded the clean tracked subproject, reported dirty/detached/no-upstream/diverged/failed subprojects by path with fix-it commands, never forced a diverged merge, and correctly supported --dry-run, --json, --sure, and --recursive."
