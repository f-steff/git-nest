#!/bin/sh
# Unit test: default_target_branch, first_line, and ticket_from_branch
# Coverage: default_target_branch, first_line, ticket_from_branch

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# default_target_branch: infers without assuming any branch name.
# The default mock's catch-all symbolic-ref response is "main", so the
# origin/HEAD symref path resolves to main.
assert_eq "$(default_target_branch ".")" "main" "origin/HEAD symref default"

# The remote HEAD symref wins with whatever name it carries.
mock_git_response "symbolic-ref" "--quiet" "refs/remotes/origin/HEAD" "refs/remotes/origin/trunk"
assert_eq "$(default_target_branch ".")" "trunk" "remote HEAD symref name is used"

# A single local branch (whatever name git init created) is the answer
# when no remote HEAD exists.
mock_git_response "symbolic-ref" "--quiet" "refs/remotes/origin/HEAD" ""
mock_git_response "for-each-ref" "--format=%(refname:short)" "refs/remotes/origin/*" ""
mock_git_response "for-each-ref" "--format=%(refname:short)" "refs/heads" "release/candidate"
assert_eq "$(default_target_branch ".")" "release/candidate" "sole local branch is used"

# The current branch answers before the last-resort fallback.
mock_git_response "for-each-ref" "--format=%(refname:short)" "refs/heads" ""
mock_git_response "symbolic-ref" "--quiet" "--short" "HEAD" "develop"
assert_eq "$(default_target_branch ".")" "develop" "current branch is used"

# Nothing to infer from: the absolute last resort is still main.
mock_git_response "symbolic-ref" "--quiet" "--short" "HEAD" ""
assert_eq "$(default_target_branch ".")" "main" "main is the absolute last resort"

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
