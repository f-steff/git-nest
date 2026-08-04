#!/bin/sh
# Test: the managed .gitignore block self-heals, prunes stale entries, and preserves user lines

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_gitignore_hygiene

# git-nest keeps its ignore rules in a self-healing managed block so it can own,
# canonicalize, and prune them without disturbing user-authored ignore lines.
test_step "Exercise the managed .gitignore block" "init/add/tidy must maintain a # BEGIN/# END git-nest ignores block, canonicalize subproject paths into it, heal stray entries, prune stale ones, and preserve user lines."

root=$(test_workspace contract_gitignore_hygiene)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"

# --- init creates the managed block and preserves pre-existing user lines ---
work="$root/work"
make_repo "$work"
cd "$work"
printf '*.tmp\nmydir/\n' >.gitignore
"$GIT_NEST" init >/dev/null
assert_file_contains .gitignore '# BEGIN git-nest ignores'
assert_file_contains .gitignore '# END git-nest ignores'
assert_file_contains .gitignore '**/.git/'
assert_file_contains .gitignore '.gitnest-branches'
assert_file_contains .gitignore '*.tmp'
assert_file_contains .gitignore 'mydir/'
# Transient conversion backups are ignored on demand via .git/info/exclude, so
# no recovery-backup rule should be baked into the committed .gitignore block.
assert_file_not_contains .gitignore '.gitnest-recovery'

# --- add inserts the subproject path into the block in canonical slash form ---
"$GIT_NEST" add "$remote" libs/foo >/dev/null
test "$(grep -c '^libs/foo/$' .gitignore)" = "1"

# --- add canonicalizes a stray no-slash user entry into the block (self-heal) ---
noslash="$root/noslash"
make_repo "$noslash"
cd "$noslash"
"$GIT_NEST" init >/dev/null
# A user wrote a bare no-slash ignore for what becomes a subproject path.
printf 'libs/foo\n' >>.gitignore
"$GIT_NEST" add "$remote" libs/foo >/dev/null
# The nest-owned path is canonicalized to the slash form inside the block, and
# the stray bare copy outside the block is removed (exactly one occurrence).
test "$(grep -c 'libs/foo' .gitignore)" = "1"
grep -q '^libs/foo/$' .gitignore || { printf 'UNEXPECTED RESULT: canonical libs/foo/ not present\n' >&2; exit 1; }

# --- tidy heals a nest-owned line a user pastes outside the block ---
printf 'libs/foo\n' >>.gitignore
"$GIT_NEST" tidy >/dev/null
test "$(grep -c 'libs/foo' .gitignore)" = "1"
grep -q '^libs/foo/$' .gitignore || { printf 'UNEXPECTED RESULT: tidy did not canonicalize libs/foo/\n' >&2; exit 1; }

# --- detach keeps the ignore entry; tidy prunes it after physical removal ---
detachwork="$root/detach"
make_repo "$detachwork"
cd "$detachwork"
"$GIT_NEST" init >/dev/null
printf 'keep-me/\n' >>.gitignore
"$GIT_NEST" add "$remote" libs/bar >/dev/null
git add .gitnest .gitignore .gitattributes >/dev/null 2>&1
git commit -m init >/dev/null
"$GIT_NEST" detach libs/bar >/dev/null
# Detach keeps the entry in the block so it stays nest-owned and prunable.
grep -q '^libs/bar/$' .gitignore || { printf 'UNEXPECTED RESULT: detach dropped the ignore entry\n' >&2; exit 1; }
# doctor warns while the folder is still present? No: a present detached repo is
# retained. Remove the folder to make the entry stale, then doctor should warn.
rm -rf libs/bar
"$GIT_NEST" doctor --offline >doctor.out 2>doctor.err || true
assert_file_contains doctor.out 'gitignore-stale'
# tidy prunes the stale entry, reports it, and keeps user lines.
"$GIT_NEST" tidy >tidy.out
assert_file_contains tidy.out 'Pruned stale ignore entry: libs/bar/'
assert_file_not_contains .gitignore 'libs/bar'
assert_file_contains .gitignore 'keep-me/'
# The managed block and constants survive pruning.
assert_file_contains .gitignore '# BEGIN git-nest ignores'
assert_file_contains .gitignore '**/.git'

describe_result "The managed .gitignore block was created, canonicalized subproject paths, healed stray entries, pruned stale entries with a report, and preserved user lines."
