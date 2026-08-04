#!/bin/sh
# Unit test: sleep_ms, regex_escape, utc_now
# Coverage: sleep_ms, regex_escape, utc_now

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# sleep_ms: converts milliseconds to fractional seconds using awk.
# We cannot verify the sleep actually happened, but we can verify the
# conversion is correct by checking it does not error on valid input.
# Calling sleep_ms with a small value tests the awk pipeline.
set +e
sleep_ms 100
_sm_rc=$?
set -e
assert_eq "$_sm_rc" "0" "sleep_ms 100ms succeeds"

# regex_escape: escapes regex metacharacters with backslashes.
assert_eq "$(regex_escape 'foo')" "foo" "plain string unchanged"
assert_eq "$(regex_escape 'foo.bar')" 'foo\.bar' "dot escaped"
assert_eq "$(regex_escape 'foo*bar')" 'foo\*bar' "star escaped"
assert_eq "$(regex_escape 'foo[bar]')" 'foo\[bar\]' "brackets escaped"
assert_eq "$(regex_escape 'foo^bar$')" 'foo\^bar\$' "anchors escaped"
assert_eq "$(regex_escape 'foo(bar)')" 'foo\(bar\)' "parens escaped"

# utc_now: outputs an ISO-8601 timestamp. Verify the format:
# YYYY-MM-DDThh:mm:ssZ
_utc=$(utc_now)
printf '%s\n' "$_utc" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || {
    echo "FAIL: utc_now malformed: $_utc" >&2
    exit 1
}

printf 'All tests passed.\n'
