#!/bin/sh
# Test: absorb --subrepo converts a git-subrepo (.gitrepo marker) into a managed subproject

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_option_absorb_subrepo

# --subrepo is never auto-detected: a directory with a .gitrepo file looks
# like ordinary tracked outer-repo files to plain absorb, so the conversion
# must be requested explicitly. It reads the remote/branch from .gitrepo,
# removes the marker, and produces a fresh single-commit subproject.
test_step "Exercise absorb --subrepo detection, guards, and conversion" "A git-subrepo directory must only convert when --subrepo is given, must read its remote/branch from .gitrepo, and must refuse dirty, already-managed, or non-subrepo paths."

root=$(test_workspace command_option_absorb_subrepo)
outer="$root/outer"
remote_thing="$root/remotes/thing.git"
remote_override="$root/remotes/override.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_thing" "$root/seed/thing"
make_bare_remote "$remote_override" "$root/seed/override"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "init nest" >/dev/null

# --- Set up a directory that looks like a git-subrepo ---
mkdir -p vendor/thing
printf 'hello\n' >vendor/thing/a.txt
cat >vendor/thing/.gitrepo <<EOF
[subrepo]
	remote = $remote_thing
	branch = main
	commit = 0000000000000000000000000000000000000000
	parent = 1111111111111111111111111111111111111111
	method = merge
	cmdver = 0.4.6
EOF
git add vendor/thing
git commit -m "add vendor/thing as a fake git-subrepo" >/dev/null

# --- Guard: plain absorb does not treat a .gitrepo directory specially ---
test_step "Do not auto-detect a subrepo under plain absorb" "Without --subrepo, a .gitrepo directory is ordinary outer-repo files and still needs a remote URL like any other files source."
run_fail "plain absorb on a subrepo path still needs a URL" any -- sh -c '"$1" absorb vendor/thing >plain.out 2>plain.err' sh "$GIT_NEST"
assert_file_contains plain.err 'needs a remote URL'

# --- Dry-run reports the .gitrepo-derived remote and branch without writing ---
test_step "Dry-run reports the planned subrepo absorption" "--dry-run must read remote/branch from .gitrepo and report the plan without touching the manifest or removing .gitrepo."
run_capture "subrepo dry-run reports the plan" dry.out dry.err -- "$GIT_NEST" absorb --subrepo vendor/thing --dry-run
assert_file_contains dry.out "Would absorb subrepo vendor/thing"
assert_file_contains dry.out "$remote_thing"
assert_file_not_contains .gitnest '[subproject "vendor/thing"]'
test -f vendor/thing/.gitrepo

# --- Dry-run JSON reports the shared envelope with the subrepo source type ---
test_step "Dry-run JSON reports the shared envelope" "--subrepo --json must emit code A and state subrepo so tooling can distinguish this source."
run_capture "subrepo dry-run JSON" dry.json dry.json.err -- "$GIT_NEST" absorb --subrepo vendor/thing --dry-run --json
assert_file_contains dry.json '"command":"absorb"'
assert_file_contains dry.json '"code":"A"'
assert_file_contains dry.json '"state":"subrepo"'
assert_file_contains dry.json '"path":"vendor/thing"'
python -m json.tool dry.json >/dev/null 2>&1 || python3 -m json.tool dry.json >/dev/null 2>&1 || true

# --- Guard: a directory without .gitrepo is refused ---
test_step "Refuse --subrepo on a directory without a .gitrepo file" "--subrepo must not silently fall back to the files source; it should explain the marker is missing and suggest the alternatives."
mkdir -p vendor/plain
printf 'x\n' >vendor/plain/x.txt
git add vendor/plain
git commit -m "add vendor/plain" >/dev/null
run_fail "missing .gitrepo refused" any -- sh -c '"$1" absorb --subrepo vendor/plain >noplain.out 2>noplain.err' sh "$GIT_NEST"
assert_file_contains noplain.err 'has no .gitrepo file'

# --- Guard: file-only options that do not apply to --subrepo are rejected ---
test_step "Reject options that do not apply to --subrepo" "--branch, --preserve-history, and --push only make sense elsewhere; the branch and remote for a subrepo come from .gitrepo."
run_fail "branch option refused on subrepo source" any -- sh -c '"$1" absorb --subrepo vendor/thing --branch dev >optb.out 2>optb.err' sh "$GIT_NEST"
assert_file_contains optb.err 'do not apply to --subrepo'

# --- Guard: dirty working tree under the path is refused without --force ---
test_step "Refuse a dirty subrepo path without --force" "Uncommitted staged, unstaged, or untracked content under the path must be resolved or explicitly overridden before conversion."
printf 'untracked\n' >vendor/thing/untracked.txt
run_fail "untracked content refused" any -- sh -c '"$1" absorb --subrepo vendor/thing >dirty.out 2>dirty.err' sh "$GIT_NEST"
assert_file_contains dirty.err 'has untracked files'
rm -f vendor/thing/untracked.txt

# --- Actual conversion: reads remote/branch from .gitrepo, removes the marker ---
test_step "Absorb the subrepo using its recorded remote" "The resulting subproject must use the .gitrepo remote and branch, start as a fresh single commit, and no longer carry the .gitrepo marker."
run_ok "subrepo absorbed using its recorded remote" -- "$GIT_NEST" absorb --subrepo vendor/thing
assert_file_contains .gitnest '[subproject "vendor/thing"]'
assert_file_contains .gitnest "repo=$remote_thing"
assert_file_contains .gitnest 'target_branch=main'
assert_file_contains .gitignore 'vendor/thing/'
test -d vendor/thing/.git
test ! -f vendor/thing/.gitrepo
thing_log_count=$(git -C vendor/thing log --oneline | wc -l)
[ "$thing_log_count" -eq 1 ] || {
    printf 'UNEXPECTED RESULT: expected a fresh single-commit subproject, found %s commits\n' "$thing_log_count" >&2
    exit 1
}

# --- Guard: an already-managed path is refused, pointing to inline/detach/remove ---
test_step "Refuse re-absorbing an already-managed subrepo path" "Reusing --subrepo on a managed path must not run the opposite conversion; it should point to inline/detach/remove."
run_fail "already-managed subrepo path refused" any -- sh -c '"$1" absorb --subrepo vendor/thing >managed.out 2>managed.err' sh "$GIT_NEST"
assert_file_contains managed.err 'already a nest subproject'
assert_file_contains managed.err 'git-nest inline'

# --- Explicit remote URL overrides the .gitrepo-recorded remote ---
test_step "An explicit remote URL overrides the .gitrepo remote" "Passing <remote-url> must take precedence over the marker's own recorded remote, matching the plain absorb convention."
mkdir -p vendor/second
printf 'second\n' >vendor/second/b.txt
cat >vendor/second/.gitrepo <<EOF
[subrepo]
	remote = $remote_thing
	branch = main
	commit = 2222222222222222222222222222222222222222
	parent = 3333333333333333333333333333333333333333
	method = merge
	cmdver = 0.4.6
EOF
git add vendor/second
git commit -m "add vendor/second as a fake git-subrepo" >/dev/null
run_ok "subrepo absorbed with an explicit URL override" -- "$GIT_NEST" absorb --subrepo vendor/second "$remote_override"
assert_file_contains .gitnest '[subproject "vendor/second"]'
assert_file_contains .gitnest "repo=$remote_override"

# --- Mutual exclusion with --subtree ---
test_step "Refuse combining --subrepo and --subtree" "The two conversions are mutually exclusive; the flags cannot be combined in one invocation."
mkdir -p vendor/third
printf 'third\n' >vendor/third/c.txt
git add vendor/third
git commit -m "add vendor/third" >/dev/null
run_fail "mutually exclusive flags refused" any -- sh -c '"$1" absorb --subrepo --subtree vendor/third >mutex.out 2>mutex.err' sh "$GIT_NEST"
assert_file_contains mutex.err 'mutually exclusive'

describe_result "absorb --subrepo correctly read .gitrepo metadata, enforced its guards, and converted a git-subrepo into a fresh single-commit subproject."
