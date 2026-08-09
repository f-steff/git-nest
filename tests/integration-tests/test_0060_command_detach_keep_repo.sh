#!/bin/sh
# Test: detach removes a subproject from the nest but keeps its checkout as a standalone repo

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_detach_keep_repo

# detach removes a subproject from the nest but keeps its checkout on disk as a
# standalone, still-ignored Git repository. It is the non-destructive inverse of
# absorbing an existing repository.
test_step "Exercise detach keep-repo behavior" "detach must drop the manifest entry, keep the files and ignore entry, report machine output, and refuse unknown paths."

root=$(test_workspace command_detach_keep_repo)
outer="$root/outer"
remote_one="$root/remotes/one.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_one" "$root/seed/one"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote_one" libs/one >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "init workspace" >/dev/null
one_head=$(git -C libs/one rev-parse HEAD)

# --- Error path: detaching an unmanaged path fails clearly ---
test_step "Refuse detaching an unmanaged path" "detach only operates on managed subprojects."
run_fail "unmanaged path refused" any -- sh -c '"$1" detach libs/missing >missing.out 2>missing.err' sh "$GIT_NEST"
assert_file_contains missing.err 'is not a tracked subproject'

# --- Dry-run reports the plan and writes nothing ---
test_step "Dry-run detach reports the plan" "A dry-run must not change the manifest or filesystem."
run_capture "detach dry-run reports the plan" dry.out dry.err -- "$GIT_NEST" detach libs/one --dry-run
assert_file_contains dry.out 'Would detach libs/one'
assert_file_contains .gitnest '[subproject "libs/one"]'

# --- JSON output ---
test_step "Detach reports machine-readable JSON" "detach --json must emit the shared envelope with the detached path."
run_capture "detach dry-run with JSON output" dj.json dj.err -- "$GIT_NEST" detach libs/one --dry-run --json
assert_file_contains dj.json '"command":"detach"'
assert_file_contains dj.json '"dry_run":true'
assert_file_contains dj.json '"code":"T"'
assert_file_contains dj.json '"path":"libs/one"'
assert_file_contains .gitnest '[subproject "libs/one"]'

# --- Real detach keeps the checkout as a standalone, ignored repository ---
test_step "Detach keeps the checkout" "After detach the manifest entry is gone but the files, the .git directory, and the ignore entry remain."
run_ok "subproject detached and checkout kept" -- "$GIT_NEST" detach libs/one
assert_file_not_contains .gitnest '[subproject "libs/one"]'
test -d libs/one/.git
assert_file_contains .gitignore 'libs/one/'
# The kept commit must be intact; detach never rewrites the standalone repo.
test "$(git -C libs/one rev-parse HEAD)" = "$one_head"
# status should now treat the kept checkout as an unmanaged nested repo.
run_capture "status reports the kept checkout as unmanaged" status.out status.err -- "$GIT_NEST" status --porcelain
assert_file_contains status.out 'U	libs/one	unmanaged	-	-	-	nested-git-repo'

# survey labels the kept checkout as a detached former subproject because its
# path still carries a nest-owned ignore entry.
run_capture "survey labels the detached repo" disc.out disc.err -- "$GIT_NEST" survey --porcelain
assert_file_contains disc.out 'D	libs/one	detached'

# --- Round trip: the detached repo can be absorbed back into the nest ---
test_step "Re-absorb the detached repository" "detach and absorb form a round trip for an existing repository."
run_ok "detached repo absorbed back into the nest" -- "$GIT_NEST" absorb libs/one
assert_file_contains .gitnest '[subproject "libs/one"]'

describe_result "detach dropped the manifest entry while preserving the checkout, reported machine output, and round-tripped with absorb."
