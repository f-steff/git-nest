#!/bin/sh
# Unit test: infer_export_format and validate_export_format
# Coverage: infer_export_format, validate_export_format

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-conversion.sh"

# infer_export_format: guesses the format from the output path extension.
assert_eq "$(infer_export_format 'build/source.tar.gz')" "tar.gz" ".tar.gz => tar.gz"
assert_eq "$(infer_export_format 'build/source.tgz')" "tar.gz" ".tgz => tar.gz"
assert_eq "$(infer_export_format 'build/source.zip')" "zip" ".zip => zip"
assert_eq "$(infer_export_format 'build/dir/')" "dir" "trailing slash => dir"
assert_eq "$(infer_export_format 'build/naked')" "dir" "no extension => dir"

# validate_export_format: only accepts tar.gz, zip, dir.
assert_ok "tar.gz is valid" -- validate_export_format "tar.gz"
assert_ok "zip is valid" -- validate_export_format "zip"
assert_ok "dir is valid" -- validate_export_format "dir"

# Invalid format must abort.
assert_fail "invalid format is rejected" -- sh -c '
    . "$1/bin/lib/git-nest-conversion.sh" 2>/dev/null
    validate_export_format "invalid"
' sh "$REPO_ROOT"

printf 'All tests passed.\n'
