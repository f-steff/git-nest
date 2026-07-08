#!/bin/sh

set -eu

# Resolve paths from the runner location so the suite works from any cwd.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=${TEST_ROOT:-"${TMPDIR:-/tmp}/git-nest-test-workspaces"}
TEST_WATCHDOG_SECONDS=${TEST_WATCHDOG_SECONDS:-180}
PATH="$REPO_ROOT/bin:$PATH"
export PATH

# Make Git's external-command discovery find the workspace git-nest binary.
chmod +x "$REPO_ROOT/bin/git-nest" 2>/dev/null || true

# Clean only the known persistent test workspace root, then leave new fixtures
# in place after the run for inspection. Keep it outside the tool repository so
# startup tests in non-Git folders are not pulled up to the tool repo root.
case "$TEST_ROOT" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) echo "Refusing to use test root inside repository: $TEST_ROOT" >&2; exit 1 ;;
    */git-nest-test-workspaces) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to remove unexpected test root: $TEST_ROOT" >&2; exit 1 ;;
esac
mkdir -p "$TEST_ROOT"
SUMMARY_MD="$REPO_ROOT/test-result.md"
suite_started=$(date +%s)
{
    printf '# git-nest Test Result\n\n'
    printf '%s\n' "- Test root: \`$TEST_ROOT\`"
    printf '%s\n\n' "- Started: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`"
    printf '%s\n\n' "- No-output watchdog: \`${TEST_WATCHDOG_SECONDS}s\`"
    printf '| No. | Test | Status | Time | Log |\n'
    printf '| --- | --- | --- | ---: | --- |\n'
} >"$SUMMARY_MD"

underline_for() {
    printf '%s\n' "$1" | sed 's/./-/g'
}

print_summary_row() {
    printf '| %-4s | %-38s | %-7s | %8s |\n' "$1" "$2" "$3" "$4"
}

append_summary_markdown_row() {
    printf '| %s | `%s` | %s | %s | `%s` |\n' "$1" "$2" "$3" "$4" "$5" >>"$SUMMARY_MD"
}

print_result() {
    printf '\nResult: %s (%s)\n' "$1" "$2"
}

stream_new_output() {
    output_file=$1
    line_count=$(wc -l <"$output_file" 2>/dev/null || printf '0')
    line_count=$(printf '%s' "$line_count" | tr -d ' ')
    if [ "$line_count" -gt "$STREAM_PRINTED_LINES" ]; then
        sed -n "$((STREAM_PRINTED_LINES + 1)),${line_count}p" "$output_file"
        STREAM_PRINTED_LINES=$line_count
    fi
}

run_test_with_watchdog() {
    test_script=$1
    output_file=$2
    : >"$output_file"
    TEST_ROOT="$TEST_ROOT" TEST_NUMBER="$test_number" TEST_RUNNER_HEADING=1 sh "$test_script" >"$output_file" 2>&1 </dev/null &
    child=$!
    last_size=0
    STREAM_PRINTED_LINES=0
    quiet_since=$(date +%s)
    while kill -0 "$child" 2>/dev/null; do
        sleep 1
        now=$(date +%s)
        size=$(wc -c <"$output_file" 2>/dev/null || printf '0')
        size=$(printf '%s' "$size" | tr -d ' ')
        stream_new_output "$output_file"
        if [ "$size" -ne "$last_size" ]; then
            last_size=$size
            quiet_since=$now
        elif [ $((now - quiet_since)) -gt "$TEST_WATCHDOG_SECONDS" ]; then
            kill "$child" 2>/dev/null || true
            wait "$child" 2>/dev/null || true
            printf 'Error: test produced no output for more than %s seconds; treating as hung\n' "$TEST_WATCHDOG_SECONDS" >>"$output_file"
            stream_new_output "$output_file"
            return 124
        fi
    done
    set +e
    wait "$child"
    rc=$?
    set -e
    stream_new_output "$output_file"
    return "$rc"
}

results="$TEST_ROOT/.run-all-results"
: >"$results"
passed=0
failed=0
skipped=0
hung=0
stop_after_hang=0

# Run every integration test in a deterministic shell environment. Numbered
# folders make it easy to correlate output workspaces with execution order.
n=1
for t in "$SCRIPT_DIR"/test_*.sh; do
    test_number=$(printf '%02d' "$n")
    test_name=$(basename "$t" .sh)
    heading="TEST $test_number $test_name"
    output="$TEST_ROOT/.run-all-$test_number.out"

    printf '\n%s\n' "$heading"
    underline_for "$heading"

    start=$(date +%s)
    if run_test_with_watchdog "$t" "$output"; then
        status=PASS
        if grep '^SKIP ' "$output" >/dev/null 2>&1; then
            status=SKIP
        fi
    else
        rc=$?
        status=FAIL
        if [ "$rc" -eq 124 ]; then
            hung=$((hung + 1))
            stop_after_hang=1
        fi
    fi
    end=$(date +%s)
    elapsed=$((end - start))
    print_result "$status" "${elapsed}s"

    case "$status" in
        PASS) passed=$((passed + 1)) ;;
        FAIL) failed=$((failed + 1)) ;;
        SKIP) skipped=$((skipped + 1)) ;;
    esac
    printf '%s|%s|%s|%ss\n' "$test_number" "$test_name" "$status" "$elapsed" >>"$results"
    append_summary_markdown_row "$test_number" "$test_name" "$status" "${elapsed}s" "$output"
    [ "$stop_after_hang" -eq 0 ] || break
    n=$((n + 1))
done

# Smoke-test direct and Git-style invocation after bin/ was added to PATH.
if [ "$stop_after_hang" -eq 0 ]; then
    test_number=$(printf '%02d' "$n")
    test_name=invocation_smoke
    heading="TEST $test_number $test_name"
    output="$TEST_ROOT/.run-all-$test_number.out"
    printf '\n%s\n' "$heading"
    underline_for "$heading"
    start=$(date +%s)
    expected_version='git-nest 0.8.0 \\_oOO_//'
    if {
        sh "$REPO_ROOT/bin/git-nest" --help >/dev/null
        test "$(sh "$REPO_ROOT/bin/git-nest" version)" = "$expected_version"
        test "$(sh "$REPO_ROOT/bin/git-nest" --version)" = "$expected_version"
        test "$(git nest version)" = "$expected_version"
    } >"$output" 2>&1 </dev/null; then
        status=PASS
    else
        status=FAIL
    fi
    end=$(date +%s)
    elapsed=$((end - start))
    cat "$output"
    print_result "$status" "${elapsed}s"
    case "$status" in
        PASS) passed=$((passed + 1)) ;;
        FAIL) failed=$((failed + 1)) ;;
    esac
    printf '%s|%s|%s|%ss\n' "$test_number" "$test_name" "$status" "$elapsed" >>"$results"
    append_summary_markdown_row "$test_number" "$test_name" "$status" "${elapsed}s" "$output"
fi

total=$((passed + failed + skipped))
suite_finished=$(date +%s)
suite_elapsed=$((suite_finished - suite_started))
printf '\nTest Summary\n'
printf '%s\n' '------------'
print_summary_row "No." "Test" "Status" "Time"
print_summary_row "----" "--------------------------------------" "-------" "--------"
while IFS='|' read -r number name status time; do
    print_summary_row "$number" "$name" "$status" "$time"
done <"$results"
printf '\nExecuted: %s, Passed: %s, Failed: %s, Skipped: %s\n' "$total" "$passed" "$failed" "$skipped"
printf 'Total time: %ss\n' "$suite_elapsed"
printf 'Test workspaces left in %s\n' "$TEST_ROOT"
{
    printf '\n'
    printf '%s\n' "- Finished: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`"
    printf '%s\n' "- Total time: \`${suite_elapsed}s\`"
    printf '%s\n' "- Executed: \`$total\`"
    printf '%s\n' "- Passed: \`$passed\`"
    printf '%s\n' "- Failed: \`$failed\`"
    printf '%s\n' "- Skipped: \`$skipped\`"
    printf '%s\n' "- Hung: \`$hung\`"
    printf '%s\n' "- Test workspaces: \`$TEST_ROOT\`"
} >>"$SUMMARY_MD"

[ "$failed" -eq 0 ]
