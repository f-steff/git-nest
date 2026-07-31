#!/bin/sh
# Unit test: emit_json_result, json_single_row_result, temp_for
# Coverage: emit_json_result, json_single_row_result, json_rows_from_porcelain_file

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# emit_json_result: builds a JSON envelope from row files.
_rows=$(mktemp)
_errors=$(mktemp)
_warnings=$(mktemp)
printf 'R\tlibs/foo\tclean\tmain\tabc123\tv1.0\thttps://example.invalid/foo.git\n' >"$_rows"

_json=$(emit_json_result "list" 0 1 "$_rows" "$_errors" "$_warnings" 0)
printf '%s\n' "$_json" | grep -qF '"command":"list"' || { echo "FAIL: command field" >&2; exit 1; }
printf '%s\n' "$_json" | grep -qF '"libs/foo"' || { echo "FAIL: subproject field" >&2; exit 1; }
printf '%s\n' "$_json" | grep -qF '"ok":true' || { echo "FAIL: ok field" >&2; exit 1; }
rm -f "$_rows" "$_errors" "$_warnings"

# json_single_row_result: wraps a single porcelain row in the JSON envelope.
# Takes 9 positional args + optional 10th.
_jsr=$(json_single_row_result 0 "absorb" 1 "A" "libs/foo" "files" "main" "abc123" "https://example.invalid/foo.git")
printf '%s\n' "$_jsr" | grep -qF '"command":"absorb"' || { echo "FAIL: command field" >&2; exit 1; }
printf '%s\n' "$_jsr" | grep -qF '"A"' || { echo "FAIL: code field" >&2; exit 1; }

printf 'All tests passed.\n'
