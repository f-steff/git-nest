#!/bin/sh
# Unit test: shell_quote wraps values containing shell metacharacters in single quotes
# Coverage: shell_quote

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# shell_quote is designed for paths and file-system names. Safe characters
# (alphanumeric plus . / := , @ % + -) pass through unquoted.
assert_eq "$(shell_quote "libs/foo")" "libs/foo" "plain path unquoted"
assert_eq "$(shell_quote "foo.bar")" "foo.bar" "dotted name unquoted"
assert_eq "$(shell_quote "test-case")" "test-case" "hyphen unquoted"
assert_eq "$(shell_quote "foo_bar")" "foo_bar" "underscore unquoted"
assert_eq "$(shell_quote "foo+bar@host")" "foo+bar@host" "plus and at safe"
assert_eq "$(shell_quote "abc123")" "abc123" "alphanumeric unquoted"
assert_eq "$(shell_quote "foo:bar")" "foo:bar" "colon unquoted"
assert_eq "$(shell_quote "foo=bar")" "foo=bar" "equals unquoted"
assert_eq "$(shell_quote "foo,bar")" "foo,bar" "comma unquoted"
assert_eq "$(shell_quote "foo%bar")" "foo%bar" "percent unquoted"

# Metacharacters (space, star, empty) trigger single-quote wrapping.
assert_eq "$(shell_quote "foo bar")" "'foo bar'" "space quoted"
assert_eq "$(shell_quote "path with spaces")" "'path with spaces'" "multiple spaces"
assert_eq "$(shell_quote "foo*")" "'foo*'" "wildcard quoted"
assert_eq "$(shell_quote "")" "''" "empty string quoted"

printf 'All tests passed.\n'
