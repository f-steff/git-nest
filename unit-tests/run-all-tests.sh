#!/bin/sh
#
# Unit test runner. Discovers and executes unit-test_*.sh files in the
# current directory. Supports list, only, except, help commands, and
# --verbose/--stop-on-fail/--no-coverage options.
#
# Run from the unit-tests/ directory or via the main test runner with --unit-tests.
#
# ASCII only.

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

: "${TMPDIR:=/tmp}"
UNIT_TEST_ROOT="${TMPDIR}/git-nest-unit-test-workspaces"
mkdir -p "$UNIT_TEST_ROOT"

# --- option parsing ---

VERBOSE=0
STOP_ON_FAIL=0
NO_COVERAGE=0
COMMAND=all
ONLY_IDS=
EXCEPT_IDS=

while [ $# -gt 0 ]; do
    case "$1" in
    --verbose|-v) VERBOSE=1; shift ;;
    --stop-on-fail) STOP_ON_FAIL=1; shift ;;
    --no-coverage) NO_COVERAGE=1; shift ;;
    list|only|except|help)
        COMMAND=$1; shift
        [ "$COMMAND" = "help" ] || [ "$COMMAND" = "list" ] && continue
        [ $# -ge 1 ] || { printf 'Error: %s requires argument(s)\n' "$COMMAND" >&2; exit 2; }
        case "$COMMAND" in
            only) ONLY_IDS=$1 ;;
            except) EXCEPT_IDS=$1 ;;
        esac
        shift
        ;;
    --*) printf 'Error: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *) printf 'Error: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# --- discover test files ---

DISCOVERED=
for _f in "$SCRIPT_DIR"/unit-test_*.sh; do
    [ -f "$_f" ] || continue
    _basename=$(basename -- "$_f")
    _id=${_basename#unit-test_}
    _id=${_id%%_*}
    DISCOVERED="$DISCOVERED $_id"
done

# Sort by ID.
DISCOVERED=$(printf '%s\n' $DISCOVERED | sort -n | tr '\n' ' ')

# --- filter by only/except ---

filtered_ids() {
    _fi_ids=$1
    _fi_only=$2
    _fi_except=$3
    _result=
    for _fi_id in $_fi_ids; do
        if [ -n "$_fi_only" ]; then
            case ",$_fi_only," in *",$_fi_id,"*) ;; *) continue ;; esac
        fi
        if [ -n "$_fi_except" ]; then
            case ",$_fi_except," in *",$_fi_id,"*) continue ;; esac
        fi
        _result="$_result $_fi_id"
    done
    printf '%s\n' "$_result" | tr ' ' '\n' | sed '/^$/d'
}

# --- list command ---

if [ "$COMMAND" = "list" ]; then
    for _lid in $(filtered_ids "$DISCOVERED" "$ONLY_IDS" "$EXCEPT_IDS"); do
        _lifile=$(ls "$SCRIPT_DIR"/unit-test_${_lid}_*.sh 2>/dev/null || true)
        [ -f "$_lifile" ] || continue
        _desc=$(sed -n '2s/^# Unit test: //p' "$_lifile")
        printf '%s  %s\n' "$_lid" "${_desc:-no description}"
    done
    exit 0
fi

# --- help ---

if [ "$COMMAND" = "help" ]; then
    printf 'Unit test runner commands:\n'
    printf '  list              List all unit tests as ID + description\n'
    printf '  only <ids>        Run only the given comma-separated IDs\n'
    printf '  except <ids>      Run all except the given comma-separated IDs\n'
    printf '  help              Print this help\n'
    printf '\nOptions:\n'
    printf '  --verbose (-v)    Stream full output instead of summary\n'
    printf '  --stop-on-fail    Stop at the first failing test\n'
    printf '  --no-coverage     Skip coverage report\n'
    exit 0
fi

# --- coverage: scan source and test coverage headers ---

compute_coverage() {
    if [ "$NO_COVERAGE" -eq 1 ]; then
        return 0
    fi
    printf '\n--- Coverage Report ---\n'

    # Extract all function definitions from bin/lib/*.sh
    _cov_all=$(mktemp)
    grep -h '^[a-z_][a-z0-9_]*()' "$REPO_ROOT"/bin/lib/*.sh | sed 's/()//' | sort -u >"$_cov_all"
    # Normalise awk-style "name() {" to "name".
    sed -i 's/[[:space:]]*{//' "$_cov_all"

    # Extract all # Coverage: headers from unit test files
    _cov_tested=$(mktemp)
    for _ctf in "$SCRIPT_DIR"/unit-test_*.sh; do
        [ -f "$_ctf" ] || continue
        grep '^# Coverage:' "$_ctf" 2>/dev/null | sed 's/^# Coverage: *//' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^('
    done | sort -u >"$_cov_tested"

    # Read deliberately untested from unit-tests.ini [untested] section.
    _cov_ini=$(mktemp)
    if [ -f "$REPO_ROOT/unit-tests/unit-tests.ini" ]; then
        sed -n '/^\[untested\]/,/^\[\(.*\)\]/{/^\[/d; /^#/d; /^$/d; p}' "$REPO_ROOT/unit-tests/unit-tests.ini" | grep -o '^[^=]*' | sort -u >"$_cov_ini"
    fi

    _cov_total=$(wc -l <"$_cov_all" | tr -d ' ')
    _cov_done=$(wc -l <"$_cov_tested" | tr -d ' ')
    _cov_untested=$(wc -l <"$_cov_ini" | tr -d ' ')
    _cov_unclassified=$((_cov_total - _cov_done - _cov_untested))

    if [ "$_cov_total" -gt 0 ]; then
        _cov_pct=$(awk -v done="$_cov_done" -v total="$_cov_total" 'BEGIN { printf "%.1f", done / total * 100 }')
    else
        _cov_pct=100.0
    fi

    printf 'Covered: %s/%s = %s%%\n' "$_cov_done" "$_cov_total" "$_cov_pct"
    printf 'Deliberately untested: %s\n' "$_cov_untested"
    printf 'Unclassified: %s\n' "$_cov_unclassified"

    # List unclassified functions (neither covered nor in ini).
    if [ "$_cov_unclassified" -gt 0 ]; then
        _cov_unclassified_list=$(comm -23 "$_cov_all" "$_cov_tested" | comm -23 - "$_cov_ini" || true)
        printf 'Unclassified functions:\n'
        printf '%s\n' "$_cov_unclassified_list" | while IFS= read -r _cu; do
            printf '  %s\n' "$_cu"
        done
    fi

    rm -f "$_cov_all" "$_cov_tested" "$_cov_ini"
}

# --- execute tests ---

EXECUTED=0
PASSED=0
FAILED=0
TOTAL_START=$(date +%s)

for _tid in $(filtered_ids "$DISCOVERED" "$ONLY_IDS" "$EXCEPT_IDS"); do
    _tfile=$(ls "$SCRIPT_DIR"/unit-test_${_tid}_*.sh 2>/dev/null || true)
    [ -f "$_tfile" ] || continue

    EXECUTED=$((EXECUTED + 1))
    _desc=$(sed -n '2s/^# Unit test: //p' "$_tfile")
    printf '  %s  %s ... ' "$_tid" "${_desc:-no description}"

    _test_start=$(date +%s)
    _ut_stdout=$(mktemp); _ut_stderr=$(mktemp)
    if {
        sh "$_tfile" >"$_ut_stdout" 2>"$_ut_stderr"
    }; then
        _test_end=$(date +%s)
        _test_time=$((_test_end - _test_start))
        printf 'PASS (%ss)\n' "$_test_time"
        PASSED=$((PASSED + 1))
    else
        _test_end=$(date +%s)
        _test_time=$((_test_end - _test_start))
        printf 'FAIL (%ss)\n' "$_test_time"
        FAILED=$((FAILED + 1))
        # Show captured stderr for debugging.
        if [ -s "$_ut_stderr" ]; then
            sed 's/^/      /' "$_ut_stderr"
        fi
        if [ "$STOP_ON_FAIL" -eq 1 ]; then
            printf 'Stopping after first failure (--stop-on-fail).\n'
            rm -f "$_ut_stdout" "$_ut_stderr"
            break
        fi
    fi
    rm -f "$_ut_stdout" "$_ut_stderr"
done

TOTAL_END=$(date +%s)
TOTAL_TIME=$((TOTAL_END - TOTAL_START))

compute_coverage
printf '\nExecuted: %s, Passed: %s, Failed: %s, Total time: %ss\n' "$EXECUTED" "$PASSED" "$FAILED" "$TOTAL_TIME"

[ "$FAILED" -eq 0 ] || exit 1
exit 0
