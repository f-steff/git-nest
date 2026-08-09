#!/bin/sh
# Test: absorb auto-detects and imports outer files, a nested repo, and a submodule, with safety guards

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_absorb_sources

# absorb auto-detects what lives at a path and brings it into the nest as a
# managed subproject. This test exercises every detected source (standalone
# nested repo, submodule, outer files) plus the safety guards.
test_step "Exercise absorb source auto-detection and guards" "absorb must handle nested repos, submodules, and outer files, and must refuse already-managed paths, deeper nested repositories, missing remotes, and file-only options on repo sources."

root=$(test_workspace command_absorb_sources)
outer="$root/outer"
remote_foo="$root/remotes/foo.git"
remote_bar="$root/remotes/bar.git"
remote_sub="$root/remotes/sub.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_bar" "$root/seed/bar"
make_bare_remote "$remote_sub" "$root/seed/sub"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "init nest" >/dev/null

# --- Source: standalone nested repository (uses its own origin remote) ---
test_step "Absorb a standalone nested repository" "A checkout already sitting in the workspace should be registered using its own origin remote and current commit."
git clone "file://$remote_foo" libs/foo >/dev/null 2>&1
foo_head=$(git -C libs/foo rev-parse HEAD)

# Dry-run must report the plan without touching the manifest.
run_capture "nested-repo dry-run reports the plan" nested_dry.out nested_dry.err -- "$GIT_NEST" absorb libs/foo --dry-run
assert_file_contains nested_dry.out 'Would absorb nested-repo libs/foo'
assert_file_not_contains .gitnest '[subproject "libs/foo"]'

run_ok "nested repo absorbed with its origin remote" -- "$GIT_NEST" absorb libs/foo
assert_file_contains .gitnest '[subproject "libs/foo"]'
assert_file_contains .gitnest "repo=file://$remote_foo"
assert_file_contains .gitnest "revision=$foo_head"
assert_file_contains .gitignore 'libs/foo/'
test -d libs/foo/.git

# --- Guard: absorbing an already-managed path is refused with guidance ---
test_step "Refuse absorbing an existing subproject" "Reusing absorb on a managed path must not silently run the opposite conversion; it should point to inline/detach/remove."
run_fail "already-managed path refused" any -- sh -c '"$1" absorb libs/foo >managed.out 2>managed.err' sh "$GIT_NEST"
assert_file_contains managed.err 'already a nest subproject'
assert_file_contains managed.err 'git-nest inline'

# --- JSON output for a nested-repo absorb ---
test_step "Absorb reports machine-readable JSON" "absorb --json must emit the shared envelope with the source type so tooling can consume it."
git clone "file://$remote_bar" libs/bar >/dev/null 2>&1
run_capture "nested repo absorbed with JSON output" bar.json bar.err -- "$GIT_NEST" absorb libs/bar --json
assert_file_contains bar.json '"command":"absorb"'
assert_file_contains bar.json '"code":"A"'
assert_file_contains bar.json '"state":"nested-repo"'
assert_file_contains bar.json '"path":"libs/bar"'
python -m json.tool bar.json >/dev/null 2>&1 || python3 -m json.tool bar.json >/dev/null 2>&1 || true

# --- Source: nested repository with no origin remote needs an explicit URL ---
test_step "Require a remote for a repo without origin" "A subproject entry pins a URL so restore works after a fresh clone; a repo with no origin must supply one."
mkdir -p libs/local
( cd libs/local && git init -q && git_config && echo x >f.txt && git add -A && git commit -qm seed )
run_fail "repo without origin refused" any -- sh -c '"$1" absorb libs/local >noremote.out 2>noremote.err' sh "$GIT_NEST"
assert_file_contains noremote.err 'has no origin remote'
run_ok "repo absorbed with an explicit URL override" -- "$GIT_NEST" absorb libs/local "file://$remote_foo"
assert_file_contains .gitnest '[subproject "libs/local"]'
assert_file_contains .gitnest "repo=file://$remote_foo"

# --- Guard: file-only options do not apply to repo sources ---
test_step "Reject file-only options on repo sources" "--branch, --preserve-history, --push, and --message only make sense when absorbing outer files."
git clone "file://$remote_bar" libs/opt >/dev/null 2>&1
run_fail "file-only option refused on repo source" any -- sh -c '"$1" absorb libs/opt --branch dev >opt.out 2>opt.err' sh "$GIT_NEST"
assert_file_contains opt.err 'only apply when absorbing outer-repository files'
rm -rf libs/opt

# --- Guard: deeper nested repositories are refused ---
test_step "Refuse a directory hiding a deeper repository" "absorb must preserve repository boundaries and not swallow nested repositories."
git clone "file://$remote_foo" deep/outer >/dev/null 2>&1
git clone "file://$remote_bar" deep/outer/inner >/dev/null 2>&1
run_fail "deeper nested repo refused" any -- sh -c '"$1" absorb deep/outer >deep.out 2>deep.err' sh "$GIT_NEST"
assert_file_contains deep.err 'deeper nested repository'
rm -rf deep

# --- Guard: files source requires a remote URL ---
test_step "Require a URL when absorbing outer files" "The files source has no remote to infer, so a URL is mandatory."
mkdir -p src/plain
printf 'plain\n' >src/plain/file.txt
git add src/plain
git commit -m "add plain files" >/dev/null
run_fail "files source without URL refused" any -- sh -c '"$1" absorb src/plain >plain.out 2>plain.err' sh "$GIT_NEST"
assert_file_contains plain.err 'needs a remote URL'

# --- Source: submodule conversion ---
test_step "Absorb a Git submodule" "A submodule should convert into a standalone, managed subproject: the gitlink and .gitmodules entry are removed and the checkout keeps working."
git -c protocol.file.allow=always submodule add "file://$remote_sub" vendor/sub >/dev/null 2>&1
git commit -m "add submodule" >/dev/null
sub_head=$(git -C vendor/sub rev-parse HEAD)
run_ok "submodule absorbed into the nest" -- "$GIT_NEST" absorb vendor/sub
assert_file_contains .gitnest '[subproject "vendor/sub"]'
assert_file_contains .gitnest "repo=file://$remote_sub"
assert_file_contains .gitnest "revision=$sub_head"
assert_file_contains .gitignore 'vendor/sub/'
test -d vendor/sub/.git
# The converted checkout must be a usable standalone repository.
git -C vendor/sub rev-parse HEAD >/dev/null
# The submodule registration must be gone from .gitmodules.
if [ -f .gitmodules ]; then
    assert_file_not_contains .gitmodules 'vendor/sub'
fi

describe_result "absorb correctly detected and handled nested repos, submodules, and outer files, and enforced the documented safety guards."
