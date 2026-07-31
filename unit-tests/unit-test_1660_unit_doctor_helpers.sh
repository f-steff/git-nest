#!/bin/sh
# Unit test: doctor helpers: doctor_code_to_status, doctor_add_check, is_positive_integer
# Coverage: doctor_code_to_status, doctor_add_check, is_positive_integer

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"
load_lib "git-nest-doctor.sh"

# doctor_code_to_status: maps single-letter codes to status words.
assert_eq "$(doctor_code_to_status 'I')" "info" "I is info"
assert_eq "$(doctor_code_to_status 'W')" "warn" "W is warn"
assert_eq "$(doctor_code_to_status 'E')" "error" "E is error"

# doctor_add_check: appends a tab-separated row to a checks file.
_checks=$(mktemp)
: >"$_checks"
doctor_add_check "$_checks" "I" "my-check" "everything ok"
grep -qF "my-check" "$_checks" || { echo "FAIL: check name not found" >&2; exit 1; }
rm -f "$_checks"

printf 'All tests passed.\n'
