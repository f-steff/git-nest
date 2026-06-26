#!/bin/sh

set -eu

# Resolve paths from the runner location so the suite works from any cwd.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=${TEST_ROOT:-"${TMPDIR:-/tmp}/git-stack-test-workspaces"}
PATH="$REPO_ROOT/bin:$PATH"
export PATH

# Make Git's external-command discovery find the workspace git-stack binary.
chmod +x "$REPO_ROOT/bin/git-stack" 2>/dev/null || true

# Clean only the known persistent test workspace root, then leave new fixtures
# in place after the run for inspection. Keep it outside the tool repository so
# startup tests in non-Git folders are not pulled up to the tool repo root.
case "$TEST_ROOT" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) echo "Refusing to use test root inside repository: $TEST_ROOT" >&2; exit 1 ;;
    */git-stack-test-workspaces) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to remove unexpected test root: $TEST_ROOT" >&2; exit 1 ;;
esac
mkdir -p "$TEST_ROOT"

underline_for() {
    printf '%s\n' "$1" | sed 's/./-/g'
}

print_summary_row() {
    printf '| %-4s | %-38s | %-7s | %8s |\n' "$1" "$2" "$3" "$4"
}

results="$TEST_ROOT/.run-all-results"
: >"$results"
passed=0
failed=0
skipped=0

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
    if TEST_ROOT="$TEST_ROOT" TEST_NUMBER="$test_number" TEST_RUNNER_HEADING=1 sh "$t" >"$output" 2>&1 </dev/null; then
        status=PASS
        if grep '^SKIP ' "$output" >/dev/null 2>&1; then
            status=SKIP
        fi
    else
        status=FAIL
    fi
    end=$(date +%s)
    elapsed=$((end - start))
    cat "$output"

    case "$status" in
        PASS) passed=$((passed + 1)) ;;
        FAIL) failed=$((failed + 1)) ;;
        SKIP) skipped=$((skipped + 1)) ;;
    esac
    printf '%s|%s|%s|%ss\n' "$test_number" "$test_name" "$status" "$elapsed" >>"$results"
    n=$((n + 1))
done

# Smoke-test direct and Git-style invocation after bin/ was added to PATH.
test_number=$(printf '%02d' "$n")
test_name=invocation_smoke
heading="TEST $test_number $test_name"
output="$TEST_ROOT/.run-all-$test_number.out"
printf '\n%s\n' "$heading"
underline_for "$heading"
start=$(date +%s)
if {
    sh "$REPO_ROOT/bin/git-stack" --help >/dev/null
    test "$(sh "$REPO_ROOT/bin/git-stack" version)" = "git-stack 0.4.1"
    test "$(sh "$REPO_ROOT/bin/git-stack" --version)" = "git-stack 0.4.1"
    test "$(git stack version)" = "git-stack 0.4.1"
} >"$output" 2>&1 </dev/null; then
    status=PASS
else
    status=FAIL
fi
end=$(date +%s)
elapsed=$((end - start))
cat "$output"
case "$status" in
    PASS) passed=$((passed + 1)) ;;
    FAIL) failed=$((failed + 1)) ;;
esac
printf '%s|%s|%s|%ss\n' "$test_number" "$test_name" "$status" "$elapsed" >>"$results"

total=$((passed + failed + skipped))
printf '\nTest Summary\n'
printf '%s\n' '------------'
print_summary_row "No." "Test" "Status" "Time"
print_summary_row "----" "--------------------------------------" "-------" "--------"
while IFS='|' read -r number name status time; do
    print_summary_row "$number" "$name" "$status" "$time"
done <"$results"
printf '\nExecuted: %s, Passed: %s, Failed: %s, Skipped: %s\n' "$total" "$passed" "$failed" "$skipped"
printf 'Test workspaces left in %s\n' "$TEST_ROOT"

[ "$failed" -eq 0 ]
