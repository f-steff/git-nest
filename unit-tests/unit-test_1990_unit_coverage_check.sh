#!/bin/sh
# Unit test: verifies every function is either covered by unit tests or listed
# in unit-tests.ini [untested]. Must run with maximum ID so it does tests
# accumulate in order 1000-1990 and this one verifies the whole set.
# Coverage: (none -- this test validates the test suite itself)

set -eu
UNIT_TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$UNIT_TESTS_DIR/.." && pwd)

# All function definitions from the source files.
_all_funcs=$(mktemp)
grep -h '^[a-z_][a-z0-9_]*()' "$REPO_ROOT"/bin/lib/*.sh | sed 's/()//' | sort -u >"$_all_funcs"
# Some function definitions use "name() {" format (awk) instead of "name()".
# Normalise by trimming whitespace and stripping trailing {.
sed -i 's/[[:space:]]*{//' "$_all_funcs"

# Covered functions from # Coverage: headers in unit test files.
_cov_funcs=$(mktemp)
: >"$_cov_funcs"
for _f in "$UNIT_TESTS_DIR"/unit-test_*.sh; do
    [ -f "$_f" ] || continue
    grep '^# Coverage:' "$_f" 2>/dev/null | sed 's/^# Coverage: *//' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^(' | sort -u >>"$_cov_funcs"
done
sort -u -o "$_cov_funcs" "$_cov_funcs"

# Deliberately untested from unit-tests.ini [untested] section.
_ini_funcs=$(mktemp)
: >"$_ini_funcs"
_ini_file="$UNIT_TESTS_DIR/unit-tests.ini"
if [ -f "$_ini_file" ]; then
    # Extract keys from the [untested] section (everything before the first =)
    sed -n '/^\[untested\]/,/^\[\(.*\)\]/{/^\[/d; /^#/d; /^$/d; p}' "$_ini_file" | grep -o '^[^=]*' | sort -u >"$_ini_funcs"
fi

# Functions that are neither covered nor in ini -- these are newly added code.
_unclassified=$(mktemp)
comm -23 "$_all_funcs" "$_cov_funcs" | comm -23 - "$_ini_funcs" >"$_unclassified" || true

_uc_count=$(wc -l <"$_unclassified" | tr -d ' ')
_total=$(wc -l <"$_all_funcs" | tr -d ' ')
_cov=$(wc -l <"$_cov_funcs" | tr -d ' ')
_ini=$(wc -l <"$_ini_funcs" | tr -d ' ')

if [ "$_uc_count" -gt 0 ]; then
    printf 'FAIL: %s function(s) are neither covered by unit tests nor listed in unit-tests.ini [untested]:\n' "$_uc_count" >&2
    while IFS= read -r _fn; do
        printf '  %s\n' "$_fn"
    done <"$_unclassified"
    printf '\nOptions to fix this:\n' >&2
    printf '  1. Write a unit test and add a # Coverage: header matching the function name\n' >&2
    printf '  2. Add a line to unit-tests.ini [untested] section: function="category: reason"\n' >&2
    printf '     where category is one of: cmd-entrypoint, trivial, pure, stateful,\n' >&2
    printf '     filesystem, arg-diff-mock, multi-step, completion, error-sink\n' >&2
    printf '  3. If the function is already covered but the name differs, check the\n' >&2
    printf '     # Coverage: header spelling matches the function definition exactly\n' >&2
    rm -f "$_all_funcs" "$_cov_funcs" "$_ini_funcs" "$_unclassified"
    exit 1
fi

rm -f "$_all_funcs" "$_cov_funcs" "$_ini_funcs" "$_unclassified"
printf 'All %s functions accounted for: %s covered + %s deliberately untested = %s\n' "$_total" "$_cov" "$_ini" "$_total"
