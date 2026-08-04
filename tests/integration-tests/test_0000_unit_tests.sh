#!/bin/sh
# Test: runs each unit test individually, streaming results line by line

set -eu
. "$(dirname "$0")/helper.sh"
test_begin unit_tests

REPO_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)

test_step "Run unit test suite" "Verify all unit test functions using the mock Git shim."

_unit_passed=0
_unit_failed=0
_unit_stderr=$(mktemp)

# Run each unit test individually so PASS/FAIL appears immediately in the
# narrative stream rather than being dumped all at once at the end.
for _ut in "$REPO_ROOT/tests/unit-tests/unit-test_"*.sh; do
    [ -f "$_ut" ] || continue
    _id=$(basename "$_ut" | sed 's/unit-test_//;s/_.*//')
    _desc=$(sed -n '2s/^# Unit test: //p' "$_ut")

    printf '  %s  %s ... ' "$_id" "${_desc:-no description}" >&9

    if sh "$_ut" >/dev/null 2>"$_unit_stderr"; then
        printf 'PASS\n' >&9
        _unit_passed=$((_unit_passed + 1))
    else
        printf 'FAIL\n' >&9
        # Show captured stderr so the user can see what went wrong.
        if [ -s "$_unit_stderr" ]; then
            sed 's/^/      /' "$_unit_stderr" >&9
        fi
        _unit_failed=$((_unit_failed + 1))
    fi
done

rm -f "$_unit_stderr"

printf '  --- Unit tests: %s passed, %s failed ---\n' "$_unit_passed" "$_unit_failed" >&9

if [ "$_unit_failed" -gt 0 ]; then
    describe_result "Unit tests: $_unit_passed passed, $_unit_failed FAILED."
    printf 'To re-run unit tests:  sh tests/unit-tests/run-all-tests.sh\n' >&9
    printf 'To re-run only this step:  sh tests/run-all-tests.sh only 0000\n' >&9
    exit 1
fi

describe_result "All $_unit_passed unit tests passed."
