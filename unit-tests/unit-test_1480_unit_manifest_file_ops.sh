#!/bin/sh
# Unit test: ensure_manifest, ensure_config, print_gitattributes_guard, line_count, status_state_for_code
# Coverage: ensure_manifest, ensure_config, print_gitattributes_guard, line_count, status_state_for_code, json_rows_from_porcelain_file, validate_survey_exclude

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"
load_lib "git-nest-doctor.sh"

# ensure_manifest: creates a minimal .gitnest if one does not exist.
ensure_manifest
assert_ok ".gitnest was created" -- test -f .gitnest
grep -qF '[project]' .gitnest || { echo "FAIL: project section missing" >&2; exit 1; }

# ensure_config: creates .gitnest-rc with defaults.
ensure_config
assert_ok ".gitnest-rc was created" -- test -f .gitnest-rc
grep -qF 'target_branch=main' .gitnest-rc || { echo "FAIL: default config" >&2; exit 1; }

# print_gitattributes_guard: writes the attribute guard block.
GITATTRIBUTES_BEGIN='# BEGIN git-nest attributes'
GITATTRIBUTES_END='# END git-nest attributes'
GITATTRIBUTES_GUARD='.gitnest text eol=lf'
_guard=$(print_gitattributes_guard)
printf '%s\n' "$_guard" | grep -qF '.gitnest text eol=lf' || { echo "FAIL: guard line" >&2; exit 1; }

# line_count: counts non-empty lines in a file.
printf 'line1\nline2\n\nline3\n' >_lc_test.txt
assert_eq "$(line_count _lc_test.txt)" "3" "line count is 3"

# status_state_for_code: maps codes to display strings.
assert_eq "$(status_state_for_code 'C')" "composite" "code C is composite"
assert_eq "$(status_state_for_code 'X')" "dirty" "unknown code is dirty"

# json_rows_from_porcelain_file: converts tab-separated rows to JSON.
printf 'M\tlibs/foo\tclean\tmain\tabc123\tv1.0\thttps://example.invalid/foo.git\n' >_jrfp_test.txt
_jsonout=$(json_rows_from_porcelain_file _jrfp_test.txt)
printf '%s\n' "$_jsonout" | grep -qF '"libs/foo"' || { echo "FAIL: json path" >&2; exit 1; }
printf '%s\n' "$_jsonout" | grep -qF '"https://example.invalid/foo.git"' || { echo "FAIL: json detail" >&2; exit 1; }

# validate_survey_exclude: only simple directory-name tokens are allowed.
assert_ok "simple exclude is ok" -- validate_survey_exclude "node_modules"
assert_ok "star exclude is ok" -- validate_survey_exclude "build*"

# Invalid excludes must abort.
assert_fail "slash in exclude is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    validate_survey_exclude "foo/bar"
' sh "$REPO_ROOT"
assert_fail "semicolon in exclude is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-manifest.sh" 2>/dev/null
    validate_survey_exclude "foo;rm"
' sh "$REPO_ROOT"

printf 'All tests passed.\n'
