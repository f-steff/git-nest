#!/bin/sh
# Unit test: json_escape, json_string, and json_row_object produce valid JSON strings
# Coverage: json_escape, json_string, json_row_object

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# json_escape: plain ASCII text passes through unchanged (no special chars).
printf 'hello' | json_escape >_escaped.txt
printf 'hello' >_expected.txt
cmp _expected.txt _escaped.txt || { echo "FAIL: plain text unchanged" >&2; exit 1; }

# json_escape: double-quote is escaped to backslash-quote.
# Write a string with a double-quote, pipe through json_escape, capture result.
printf 'a"b' | json_escape >_escaped.txt
# Expected: a\"b (3 bytes: a, backslash, double-quote, b -> 4 bytes)
# Actually: a, backslash, quote, b = 4 characters
printf 'a\\"b' >_expected.txt
cmp _expected.txt _escaped.txt || { echo "FAIL: double-quote escaped" >&2; printf 'got: '; cat _escaped.txt; exit 1; }

# json_escape: backslash itself is escaped.
printf 'a\\b' | json_escape >_escaped.txt
# Should produce: a\\b (a, backslash, backslash, b)
printf 'a\\\\b' >_expected.txt
cmp _expected.txt _escaped.txt || { echo "FAIL: backslash escaped" >&2; printf 'got: '; cat _escaped.txt; exit 1; }

# json_string: wraps a value in double quotes.
assert_eq "$(json_string 'hello')" '"hello"' "simple string wrapped"
assert_eq "$(json_string 'foo bar')" '"foo bar"' "space preserved"

# json_row_object: builds a JSON object with the shared seven-field schema.
_obj=$(json_row_object "M" "libs/foo" "clean" "main" "abc123" "v1.0" "https://example.invalid/foo.git")
printf '%s\n' "$_obj" | grep '"code"' >/dev/null || { echo "FAIL: code field missing" >&2; exit 1; }
printf '%s\n' "$_obj" | grep '"path"' >/dev/null || { echo "FAIL: path field missing" >&2; exit 1; }
printf '%s\n' "$_obj" | grep '"libs/foo"' >/dev/null || { echo "FAIL: path value missing" >&2; exit 1; }

printf 'All tests passed.\n'
