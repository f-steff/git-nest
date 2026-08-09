#!/bin/sh
#
# Unit test helper -- sourced by every unit test file.
# Provides setup/teardown, assertion API, mock support, and a clean
# temporary workspace. Unit tests run in isolation without real Git
# repositories, using the mock shim from mocks.sh instead.

set -eu

# zsh: stay in native zsh mode for reliable hash table management.

# Resolve the repository and unit test roots.
# Use BASH_SOURCE or $0 depending on the shell; both work for our purposes.
_UNIT_HELPER_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE:-$0}")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$_UNIT_HELPER_DIR/../.." && pwd)
UNIT_TESTS_DIR="$_UNIT_HELPER_DIR"

# Global variables normally set by bin/git-nest-main.sh. Tests that source library
# modules directly must provide these so the modules can find their dependencies
# (git-nest-parse.awk, git-nest-tree-render.awk) and read the correct config file.
SCRIPT_DIR="$REPO_ROOT/bin"
: "${MANIFEST_FILE:=.gitnest}"
: "${CONFIG_FILE:=.gitnest-rc}"
export MANIFEST_FILE CONFIG_FILE SCRIPT_DIR

# Exit code constants normally set by git-nest-main.sh.
# The library modules use these without defining them.
: "${EXIT_ISSUES:=1}"
: "${EXIT_USAGE:=2}"
: "${EXIT_PRECONDITION:=3}"
: "${EXIT_LOCK:=4}"
: "${EXIT_GIT:=5}"
export EXIT_ISSUES EXIT_USAGE EXIT_PRECONDITION EXIT_LOCK EXIT_GIT

# Manifest constants normally set by git-nest-main.sh.
: "${MANIFEST_SCHEMA_VERSION:=1}"
: "${JSON_SCHEMA_VERSION:=1}"
: "${GITATTRIBUTES_GUARD:=.gitnest text eol=lf}"
: "${GITATTRIBUTES_BEGIN:=# BEGIN git-nest attributes}"
: "${GITATTRIBUTES_END:=# END git-nest attributes}"
: "${GITIGNORE_BEGIN:=# BEGIN git-nest ignores}"
: "${GITIGNORE_END:=# END git-nest ignores}"
export MANIFEST_SCHEMA_VERSION JSON_SCHEMA_VERSION
export GITATTRIBUTES_GUARD GITATTRIBUTES_BEGIN GITATTRIBUTES_END
export GITIGNORE_BEGIN GITIGNORE_END

# More globals from git-nest-main.sh.
: "${BRANCH_MARKS_FILE:=.gitnest-branches}"
: "${PUSH_CANDIDATES_FILE:=.gitnest-push-candidates}"
: "${RECOVERY_BACKUP_PREFIX:=.gitnest-recovery}"
export BRANCH_MARKS_FILE PUSH_CANDIDATES_FILE RECOVERY_BACKUP_PREFIX

: "${GITIGNORE_GIT_DIR_GUARD_ONE:=**/.git/}"
: "${GITIGNORE_GIT_DIR_GUARD_TWO:=**/.git}"
: "${GIT_NEST_JSON_DRY_RUN:=0}"

# Counters to report summary at end of test run.
UNIT_PASSED=0
UNIT_FAILED=0
UNIT_LOCATION="$UNIT_TESTS_DIR"

# Load common mocks -- the test may override specific responses later.
# The mock Git shim is prepended to PATH so all git calls are intercepted.
. "$UNIT_TESTS_DIR/mocks.sh"

# --- assert helpers ---

# Compare two strings and fail with a clear message on mismatch.
assert_eq() {
    _ue_actual=$1
    _ue_expected=$2
    _ue_description=${3:-}
    if [ "$_ue_actual" != "$_ue_expected" ]; then
        printf 'UNEXPECTED RESULT: expected "%s", got "%s"%s\n' \
            "$_ue_expected" "$_ue_actual" "${_ue_description:+ ($_ue_description)}" >&2
        exit 1
    fi
}

# Run a command and fail if it exits with a nonzero code.
assert_ok() {
    _uo_description=$1
    shift
    [ "${1:-}" = "--" ] || {
        printf 'assert_ok requires -- before the command\n' >&2
        exit 1
    }
    shift
    set +e
    "$@"
    _uo_rc=$?
    set -e
    if [ "$_uo_rc" -ne 0 ]; then
        printf 'UNEXPECTED RESULT: %s -- expected exit 0, got %s for: %s\n' \
            "$_uo_description" "$_uo_rc" "$*" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$_uo_description"
}

# Run a command and fail if it exits 0 (expected failure path).
assert_fail() {
    _uf_description=$1
    shift
    [ "${1:-}" = "--" ] || {
        printf 'assert_fail requires -- before the command\n' >&2
        exit 1
    }
    shift
    set +e
    "$@"
    _uf_rc=$?
    set -e
    if [ "$_uf_rc" -eq 0 ]; then
        printf 'UNEXPECTED RESULT: %s -- expected nonzero exit, got 0 for: %s\n' \
            "$_uf_description" "$*" >&2
        exit 1
    fi
    printf 'EXPECTED FAIL: %s\n' "$_uf_description"
}

# --- setup / teardown ---

# Creates a clean temporary directory and cd's into it.
# Installs mock Git on PATH.
setup_unit_test() {
    UNIT_TEST_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/gn-unit-test.XXXXXX")
    cd "$UNIT_TEST_TEMP" || exit 1
    install_mock_git
    # Clear zsh command hash table after PATH modification so external
    # commands called from library functions (awk, cksum, etc.) are found.
    hash -r 2>/dev/null || rehash 2>/dev/null || true
}

# Removes the temporary directory and its contents, plus the mock Git shim
# directory and response table that setup_unit_test created (otherwise each
# unit test run leaks a gn-mock-git.* directory in /tmp).
teardown_unit_test() {
    [ -n "${UNIT_TEST_TEMP:-}" ] && [ -d "$UNIT_TEST_TEMP" ] && rm -rf "$UNIT_TEST_TEMP" || true
    [ -n "${MOCK_BIN:-}" ] && [ -d "$MOCK_BIN" ] && rm -rf "$MOCK_BIN" || true
    [ -n "${MOCK_RESPONSE_FILE:-}" ] && [ -f "$MOCK_RESPONSE_FILE" ] && rm -f "$MOCK_RESPONSE_FILE" || true
}

# Trap ensures teardown runs even when the test exits unexpectedly.
trap teardown_unit_test EXIT

# --- library loader ---

# Source a library module from bin/lib/ so its functions are available.
# The module path is relative to bin/lib/ (e.g. "git-nest-manifest.sh").
load_lib() {
    _ul_lib=$1
    [ -f "$REPO_ROOT/bin/lib/$_ul_lib" ] || {
        printf 'FATAL: library not found: bin/lib/%s\n' "$_ul_lib" >&2
        exit 1
    }
    # zsh caches command paths per-function at definition time. Rehash
    # before sourcing so that paths resolved during definition are fresh.
    hash -r 2>/dev/null || rehash 2>/dev/null || true
    . "$REPO_ROOT/bin/lib/$_ul_lib"
}

# zsh pre-resolves command paths inside function bodies at definition time.
# If PATH changes after a function is defined, zsh may still hold stale
# paths or "not found" entries. Clear the hash table after all sourcing.
hash -r 2>/dev/null || rehash 2>/dev/null || true
