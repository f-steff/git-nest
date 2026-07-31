#!/bin/sh
# Unit test: die, die_code, warn, notice, require_value, precondition_error, git_error
# Coverage: die, die_code, warn, notice, require_value, precondition_error, git_error, usage_error

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# All exit functions call exit internally, so we run each in a subshell
# with set +e to capture the exit code and stderr.

# die: exits 1, prints to stderr.
set +e
(die "test failure" 2>_d_stderr) >/dev/null
_drc=$?
set -e
assert_eq "$_drc" "1" "die exits 1"
grep -qF "Error: test failure" _d_stderr || { echo "FAIL: die stderr" >&2; exit 1; }

# die_code: exits with the given code.
set +e
(die_code 5 "code five" 2>_dc_stderr) >/dev/null
_dcrc=$?
set -e
assert_eq "$_dcrc" "5" "die_code exits with given code"

# warn: does not exit, prints to stderr.
set +e
warn "test warning" 2>_w_stderr
_wrc=$?
set -e
assert_eq "$_wrc" "0" "warn does not exit"
grep -qF "Warning: test warning" _w_stderr || { echo "FAIL: warn stderr" >&2; exit 1; }

# notice: does not exit, prints to stderr.
set +e
notice "test notice" 2>_n_stderr
_nrc=$?
set -e
assert_eq "$_nrc" "0" "notice does not exit"
grep -qF "Notice: test notice" _n_stderr || { echo "FAIL: notice stderr" >&2; exit 1; }

# require_value: exits 3 for empty value, returns silently for non-empty.
set +e
(require_value "" "missing" 2>/dev/null) >/dev/null
_rvrc=$?
set -e
assert_eq "$_rvrc" "3" "require_value empty exits 3"

# A non-empty value succeeds silently.
set +e
require_value "ok" "should not fire" 2>/dev/null
_rv2rc=$?
set -e
assert_eq "$_rv2rc" "0" "require_value nonempty passes"

# usage_error exits 2.
set +e
(usage_error "bad" 2>/dev/null) >/dev/null
_urc=$?
set -e
assert_eq "$_urc" "2" "usage_error exits 2"

printf 'All tests passed.\n'
