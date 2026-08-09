#!/bin/sh
# Test: absorb --subtree converts a plain tracked folder into a managed subproject

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_option_absorb_subtree

# --subtree is never auto-detected: a subtree leaves no marker file behind, so
# the caller must pass --subtree and an explicit remote URL. The conversion is
# forward-only, producing a fresh single-commit subproject just like the
# outer-repo files source.
test_step "Exercise absorb --subtree guards and conversion" "A subtree directory must only convert when --subtree is given with an explicit remote URL, and must refuse dirty or already-managed paths."

root=$(test_workspace command_option_absorb_subtree)
outer="$root/outer"
remote_thing="$root/remotes/thing.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_thing" "$root/seed/thing"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "init nest" >/dev/null

# --- Set up a plain tracked directory simulating a merged subtree ---
mkdir -p vendor/thing
printf 'hello\n' >vendor/thing/a.txt
git add vendor/thing
git commit -m "add vendor/thing as a fake subtree" >/dev/null

# --- Guard: a remote URL is mandatory since a subtree records no remote ---
test_step "Require a remote URL for --subtree" "A subtree keeps no record of its origin once merged, so the URL must be supplied explicitly."
run_fail "subtree without URL refused" any -- sh -c '"$1" absorb --subtree vendor/thing >nourl.out 2>nourl.err' sh "$GIT_NEST"
assert_file_contains nourl.err 'needs a remote URL'

# --- Dry-run reports the plan without writing ---
test_step "Dry-run reports the planned subtree absorption" "--dry-run must report the target branch and remote without touching the manifest or the working tree."
run_capture "subtree dry-run reports the plan" dry.out dry.err -- "$GIT_NEST" absorb --subtree vendor/thing "$remote_thing" --dry-run
assert_file_contains dry.out "Would absorb subtree vendor/thing"
assert_file_contains dry.out "$remote_thing"
assert_file_not_contains .gitnest '[subproject "vendor/thing"]'

# --- Dry-run JSON reports the shared envelope with the subtree source type ---
test_step "Dry-run JSON reports the shared envelope" "--subtree --json must emit code A and state subtree so tooling can distinguish this source."
run_capture "subtree dry-run JSON" dry.json dry.json.err -- "$GIT_NEST" absorb --subtree vendor/thing "$remote_thing" --dry-run --json
assert_file_contains dry.json '"command":"absorb"'
assert_file_contains dry.json '"code":"A"'
assert_file_contains dry.json '"state":"subtree"'
assert_file_contains dry.json '"path":"vendor/thing"'
python -m json.tool dry.json >/dev/null 2>&1 || python3 -m json.tool dry.json >/dev/null 2>&1 || true

# --- Guard: options that do not apply to --subtree are rejected ---
test_step "Reject options that do not apply to --subtree" "--preserve-history and --push do not apply; the conversion is always a fresh single-commit snapshot."
run_fail "preserve-history option refused on subtree source" any -- sh -c '"$1" absorb --subtree vendor/thing "$2" --preserve-history >optp.out 2>optp.err' sh "$GIT_NEST" "$remote_thing"
assert_file_contains optp.err 'do not apply to --subtree'

# --- Guard: dirty working tree under the path is refused without --force ---
test_step "Refuse a dirty subtree path without --force" "Uncommitted staged, unstaged, or untracked content under the path must be resolved or explicitly overridden before conversion."
printf 'untracked\n' >vendor/thing/untracked.txt
run_fail "untracked content refused" any -- sh -c '"$1" absorb --subtree vendor/thing "$2" >dirty.out 2>dirty.err' sh "$GIT_NEST" "$remote_thing"
assert_file_contains dirty.err 'has untracked files'
rm -f vendor/thing/untracked.txt

# --- Actual conversion: uses the explicit branch and URL ---
test_step "Absorb the subtree with an explicit branch and URL" "The resulting subproject must use the requested branch and URL and start as a fresh single commit."
run_ok "subtree absorbed with an explicit branch and URL" -- "$GIT_NEST" absorb --subtree vendor/thing "$remote_thing" --branch trunk --message "Create vendor/thing"
assert_file_contains .gitnest '[subproject "vendor/thing"]'
assert_file_contains .gitnest "repo=$remote_thing"
assert_file_contains .gitnest 'target_branch=trunk'
assert_file_contains .gitignore 'vendor/thing/'
test -d vendor/thing/.git
thing_log_count=$(git -C vendor/thing log --oneline | wc -l)
[ "$thing_log_count" -eq 1 ] || {
    printf 'UNEXPECTED RESULT: expected a fresh single-commit subproject, found %s commits\n' "$thing_log_count" >&2
    exit 1
}
git -C vendor/thing log -1 --pretty=%s | grep -F -- "Create vendor/thing" >/dev/null || {
    printf 'UNEXPECTED RESULT: expected the --message text as the initial commit subject\n' >&2
    exit 1
}

# --- Guard: an already-managed path is refused, pointing to inline/detach/remove ---
test_step "Refuse re-absorbing an already-managed subtree path" "Reusing --subtree on a managed path must not run the opposite conversion; it should point to inline/detach/remove."
run_fail "already-managed subtree path refused" any -- sh -c '"$1" absorb --subtree vendor/thing "$2" >managed.out 2>managed.err' sh "$GIT_NEST" "$remote_thing"
assert_file_contains managed.err 'already a nest subproject'
assert_file_contains managed.err 'git-nest inline'

# --- Mutual exclusion with --subrepo ---
test_step "Refuse combining --subtree and --subrepo" "The two conversions are mutually exclusive; the flags cannot be combined in one invocation."
mkdir -p vendor/second
printf 'second\n' >vendor/second/b.txt
git add vendor/second
git commit -m "add vendor/second" >/dev/null
run_fail "mutually exclusive flags refused" any -- sh -c '"$1" absorb --subtree --subrepo vendor/second "$2" >mutex.out 2>mutex.err' sh "$GIT_NEST" "$remote_thing"
assert_file_contains mutex.err 'mutually exclusive'

describe_result "absorb --subtree correctly required an explicit remote URL, enforced its guards, and converted a plain tracked folder into a fresh single-commit subproject."
