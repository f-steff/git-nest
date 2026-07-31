#!/bin/sh
# Unit test: gitattributes_has_guard, ensure_gitattributes_guard, ensure_gitignore_entry, ensure_gitignore_hygiene
# Coverage: gitattributes_has_guard, ensure_gitattributes_guard, ensure_gitignore_entry, ensure_gitignore_hygiene

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# gitattributes_has_guard: checks if .gitattributes contains the guard.
# No .gitattributes file at all means no guard.
assert_fail "no guard when file missing" -- gitattributes_has_guard

# Write a minimal .gitattributes with the guard.
printf '.gitnest text eol=lf\n' >.gitattributes
printf '.gitnest-rc text eol=lf\n' >>.gitattributes
printf 'bin/git-nest text eol=lf\n' >>.gitattributes
printf 'bin/git_nest.sh text eol=lf\n' >>.gitattributes
printf 'bin/git-nest.bat text eol=crlf\n' >>.gitattributes
assert_ok "guard detected with all five entries" -- gitattributes_has_guard

# ensure_gitattributes_guard: creates or refreshes the guard block.
# Start fresh — no .gitattributes file.
rm -f .gitattributes
assert_fail "no guard after removal" -- gitattributes_has_guard

# ensure_gitattributes_guard should create one.
ensure_gitattributes_guard
assert_ok "guard created by ensure" -- gitattributes_has_guard

# ensure_gitignore_entry: adds a path to the managed ignore block.
# First time: creates the block if .gitignore does not exist.
rm -f .gitignore
GITIGNORE_BEGIN='# BEGIN git-nest ignores'
GITIGNORE_END='# END git-nest ignores'
ensure_gitignore_entry "libs/foo"
assert_ok ".gitignore created" -- test -f .gitignore
grep -qF "libs/foo" .gitignore || { echo "FAIL: entry not added" >&2; exit 1; }

# ensure_gitignore_hygiene: reconciles the managed block.
# Should not error on a valid ignore file.
ensure_gitignore_hygiene 2>/dev/null || {
    echo "FAIL: ensure_gitignore_hygiene should succeed on valid file" >&2
    exit 1
}

printf 'All tests passed.\n'
