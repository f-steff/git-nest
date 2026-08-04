#!/bin/sh
# Unit test: default_target_branch, first_line, and ticket_from_branch
# Coverage: default_target_branch, first_line, ticket_from_branch

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# default_target_branch: checks for origin refs via show-ref.
# The default mock has show-ref for main, so it should return "main".
assert_eq "$(default_target_branch ".")" "main" "default target branch is main"

# first_line: returns the first line of a file.
printf 'line one\nline two\nline three\n' >test_lines.txt
assert_eq "$(first_line test_lines.txt)" "line one" "first line extracted"
printf '\n\nfirst nonempty\n' >test_blank.txt
# sed prints the first line even if it is blank.
assert_eq "$(first_line test_blank.txt)" "" "first line is empty if file starts blank"

# ticket_from_branch: extracts AAA-123 prefix from a branch name.
assert_eq "$(ticket_from_branch 'ABC-42-some-feature')" "ABC-42" "ticket extracted"
assert_eq "$(ticket_from_branch 'XX-999')" "XX-999" "ticket is the entire branch name"
assert_eq "$(ticket_from_branch 'feature/no-ticket')" "" "no ticket returns empty"
assert_eq "$(ticket_from_branch 'main')" "" "main has no ticket prefix"
assert_eq "$(ticket_from_branch 'abc-123-lowercase')" "" "lowercase ticket not matched"

printf 'All tests passed.\n'
