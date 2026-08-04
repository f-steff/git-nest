#!/bin/sh

set -eu

# Resolve paths from the runner location so the suite works from any cwd.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=${TEST_ROOT:-"${TMPDIR:-/tmp}/git-nest-test-workspaces"}
TEST_WATCHDOG_SECONDS=${TEST_WATCHDOG_SECONDS:-180}
PATH="$REPO_ROOT/bin:$PATH"
export PATH

# The suite must run with MSYS2 path conversion ENABLED: git.exe is a native
# Windows binary and needs POSIX->Windows conversion for /tmp workspace paths.
# Callers may have set MSYS2_ARG_CONV_EXCL or MSYS_NO_PATHCONV for their own
# shells (e.g. around docker volume mounts); neutralize them here so the test
# processes get a deterministic environment regardless of how the runner was
# invoked.
unset MSYS2_ARG_CONV_EXCL MSYS_NO_PATHCONV MSYS2_ENV_CONV_EXCL 2>/dev/null || true

# Capture the full run to a log file by default, written at the repository root
# and named after the runner. Disable with --no-log, or choose --log FILE.
LOG_FILE="$REPO_ROOT/run-all-tests.log"

# By default the console shows a curated narrative per test (step descriptions
# and each git-nest command with its output). --verbose streams the full raw
# output of every command with a shell trace. --stop-on-fail stops at the first
# failing test.
VERBOSE=0
STOP_ON_FAIL=0

# Command and its argument. Empty COMMAND means "run all tests".
COMMAND=
COMMAND_IDS=

# Print the runner's help text (commands and options) and stop.
usage() {
    cat <<'EOF'
Usage: run-all-tests.sh [options] [command]

Commands:
  (none)         Run every test.
  list           List all tests as: ID  description.
  only <ids>     Run only the comma-separated test IDs.
  except <ids>   Run every test except the comma-separated IDs.
  cleanup        Remove artifacts from previous runs and stop (no tests run).
  help           Show this help and exit.

Options:
  --verbose, -v  Stream full raw output with a shell trace (everything),
                 instead of the curated per-test narrative.
  --stop-on-fail Stop at the first failing test.
  --log[=FILE]   Write the full run to FILE (default run-all-tests.log).
  --no-log       Do not write a full-run log file.

Examples:
  run-all-tests.sh
  run-all-tests.sh list
  run-all-tests.sh only 0130,0140,5010
  run-all-tests.sh except 5000,5010,5020
  run-all-tests.sh cleanup
  run-all-tests.sh only 0250 --verbose
  run-all-tests.sh --stop-on-fail

Test IDs are the four-digit prefix of each test file (see list). An unknown
command, option, or test ID prints this help and stops.
EOF
}

# Remove every artifact a previous run may have left behind: the persistent
# test workspace root (guarded so cleanup never touches anything outside the
# known test-root pattern) and stale per-test temp dirs in the system temp
# area (leaked mock-git dirs, unit-test scratch dirs, and standalone shim
# dirs). Every run starts by calling this; the cleanup command exposes it
# standalone. Pass 1 to print a confirmation line.
cleanup_artifacts() {
    _ca_verbose=${1:-0}
    case "$TEST_ROOT" in
        "$REPO_ROOT"|"$REPO_ROOT"/*) echo "Refusing to use test root inside repository: $TEST_ROOT" >&2; exit 1 ;;
        */git-nest-test-workspaces) rm -rf "$TEST_ROOT" ;;
        *) echo "Refusing to remove unexpected test root: $TEST_ROOT" >&2; exit 1 ;;
    esac
    _ca_tmp=${TMPDIR:-/tmp}
    rm -rf "$_ca_tmp"/gn-mock-git.* "$_ca_tmp"/gn-unit-test.* "$_ca_tmp"/git-nest-shim.* 2>/dev/null || true
    # Remove the runner's generated summary and log from the repository root
    # (both are git-ignored artifacts of a previous run).
    rm -f "$REPO_ROOT/run-all-tests-results.md" "$REPO_ROOT/run-all-tests.log" 2>/dev/null || true
    if [ "$_ca_verbose" -eq 1 ]; then
        printf 'Removed test workspace %s, stale test artifacts, and run-all summary/log.\n' "$TEST_ROOT"
    fi
}

# Print the sorted paths of all numbered test files.
test_files() {
    for tf in "$SCRIPT_DIR"/integration-tests/test_[0-9][0-9][0-9][0-9]_*.sh; do
        [ -e "$tf" ] && printf '%s\n' "$tf"
    done | sort
}

# Extract the four-digit ID from a test file path.
id_of() {
    io_b=$(basename "$1")
    io_b=${io_b#test_}
    printf '%s' "${io_b%%_*}"
}

# Extract the descriptive name (after the ID) from a test file path.
name_of() {
    no_b=$(basename "$1" .sh)
    printf '%s' "${no_b#test_????_}"
}

# Read the one-line "# Test:" description header from a test file.
desc_of() {
    sed -n 's/^# Test: //p' "$1" | head -n 1
}

# --- Argument parsing: options in any position, one optional command ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-log) LOG_FILE= ;;
        --log)
            shift
            [ "$#" -gt 0 ] || { printf 'run-all-tests: --log requires a file argument\n' >&2; usage >&2; exit 2; }
            LOG_FILE=$1
            ;;
        --log=*) LOG_FILE=${1#--log=} ;;
        --verbose|-v) VERBOSE=1 ;;
        --stop-on-fail) STOP_ON_FAIL=1 ;;
        -h|--help|help) usage; exit 0 ;;
        list|only|except|cleanup)
            [ -z "$COMMAND" ] || { printf 'run-all-tests: only one command is allowed\n' >&2; usage >&2; exit 2; }
            COMMAND=$1
            ;;
        -*)
            printf 'run-all-tests: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            # A bare token is the argument to only/except (a comma-separated ID list).
            if { [ "$COMMAND" = only ] || [ "$COMMAND" = except ]; } && [ -z "$COMMAND_IDS" ]; then
                COMMAND_IDS=$1
            else
                printf 'run-all-tests: unknown command or argument: %s\n' "$1" >&2
                usage >&2
                exit 2
            fi
            ;;
    esac
    shift
done

# --- cleanup: remove artifacts from previous runs and stop (no tests run) ---
if [ "$COMMAND" = cleanup ]; then
    cleanup_artifacts 1
    exit 0
fi

# --- list: print every test as "ID  description" (no execution) ---
if [ "$COMMAND" = list ]; then
    test_files | while IFS= read -r tf; do
        printf '%s  %s\n' "$(id_of "$tf")" "$(desc_of "$tf")"
    done
    exit 0
fi

# only/except require an ID list.
if { [ "$COMMAND" = only ] || [ "$COMMAND" = except ]; } && [ -z "$COMMAND_IDS" ]; then
    printf 'run-all-tests: %s requires a comma-separated list of test IDs\n' "$COMMAND" >&2
    usage >&2
    exit 2
fi

# Validate that every requested ID exists; an unknown ID stops with the help.
# Membership is checked with grep to avoid juggling IFS between commas (the ID
# list separator) and newlines (the available-ID separator).
if [ -n "$COMMAND_IDS" ]; then
    all_ids=$(test_files | while IFS= read -r tf; do id_of "$tf"; printf '\n'; done)
    for req in $(printf '%s' "$COMMAND_IDS" | tr ',' ' '); do
        if ! printf '%s\n' "$all_ids" | grep -Fxq "$req"; then
            printf 'run-all-tests: unknown test ID: %s (use "list" to see valid IDs)\n' "$req" >&2
            usage >&2
            exit 2
        fi
    done
fi

# Report whether an ID is in the comma-separated COMMAND_IDS list.
id_selected() {
    printf '%s' "$COMMAND_IDS" | tr ',' '\n' | grep -Fxq "$1"
}

# One shim directory for the whole run. helper.sh installs a git-nest logging
# shim here so every git-nest invocation is echoed to the narrative stream.
GIT_NEST_SHIM_DIR="$TEST_ROOT/.git-nest-shim"
export GIT_NEST_SHIM_DIR

# Resolve a relative log path against the current directory so the file lands
# where the caller expects regardless of the runner location.
case "$LOG_FILE" in
    ''|/*) ;;
    *) LOG_FILE="$(pwd)/$LOG_FILE" ;;
esac

# Make Git's external-command discovery find the workspace git-nest binary.
chmod +x "$REPO_ROOT/bin/git-nest" 2>/dev/null || true

# Every run starts clean: remove the persistent test workspace root and stale
# temp artifacts from previous runs, then leave new fixtures in place after the
# run for inspection. Keep the workspace outside the tool repository so startup
# tests in non-Git folders are not pulled up to the tool repo root.
cleanup_artifacts
mkdir -p "$TEST_ROOT"
SUMMARY_MD="$REPO_ROOT/run-all-tests-results.md"

# Build the selected test list (paths) honoring only/except into a file.
SELECTED_FILE="$TEST_ROOT/.run-all-selected"
: >"$SELECTED_FILE"
test_files | while IFS= read -r tf; do
    tid=$(id_of "$tf")
    # Use if-blocks so a non-selected test does not make the loop body return
    # nonzero (which would abort the pipeline under set -e).
    case "$COMMAND" in
        only) if id_selected "$tid"; then printf '%s\n' "$tf" >>"$SELECTED_FILE"; fi ;;
        except) if id_selected "$tid"; then :; else printf '%s\n' "$tf" >>"$SELECTED_FILE"; fi ;;
        *) printf '%s\n' "$tf" >>"$SELECTED_FILE" ;;
    esac
done

# Print a heading with a matching dash underline so test headers stand out
# in the console stream without depending on terminal control codes.
underline_for() {
    printf '%s\n' "$1" | sed 's/./-/g'
}

# Build a run of N dash characters without relying on printf '%*s' (not portable
# to every POSIX printf), used for the summary separator row.
summary_dashes() {
    sd_n=$1
    sd_s=''
    while [ "$sd_n" -gt 0 ]; do
        sd_s="$sd_s-"
        sd_n=$((sd_n - 1))
    done
    printf '%s' "$sd_s"
}

# Append one markdown table row (ID, name, status, time, log link) to the
# results file so the summary is a self-contained report for CI and docs.
append_summary_markdown_row() {
    printf '| %s | `%s` | %s | %s | `%s` |\n' "$1" "$2" "$3" "$4" "$5" >>"$SUMMARY_MD"
}

# Print the per-test result line (PASS/FAIL/SKIP and elapsed seconds) to the
# console immediately after each test finishes.
print_result() {
    printf '\nResult: %s (%s)\n' "$1" "$2"
}

# Print any lines of a streaming file that were not printed yet, so the
# console shows progress incrementally instead of waiting for the whole test.
stream_new_output() {
    output_file=$1
    line_count=$(wc -l <"$output_file" 2>/dev/null || printf '0')
    line_count=$(printf '%s' "$line_count" | tr -d ' ')
    if [ "$line_count" -gt "$STREAM_PRINTED_LINES" ]; then
        sed -n "$((STREAM_PRINTED_LINES + 1)),${line_count}p" "$output_file"
        STREAM_PRINTED_LINES=$line_count
    fi
}

# Run one test as a background subprocess and watch it: stream its output as
# it appears, kill it if it produces nothing for TEST_WATCHDOG_SECONDS, and
# return its exit code (124 when treated as hung).
run_test_with_watchdog() {
    test_script=$1
    output_file=$2
    narrative_file=$3
    : >"$output_file"
    : >"$narrative_file"
    # fd 1/2 collect the full raw output into output_file (for the watchdog, the
    # per-test log, and failure dumps). fd 9 collects the curated narrative that
    # helper.sh and the git-nest shim write. In --verbose mode the test also runs
    # under a shell trace so the raw stream contains every command.
    if [ "$VERBOSE" -eq 1 ]; then
        TEST_ROOT="$TEST_ROOT" TEST_NUMBER="$test_number" TEST_RUNNER_HEADING=1 \
            sh -x "$test_script" >"$output_file" 2>&1 9>"$narrative_file" </dev/null &
    else
        TEST_ROOT="$TEST_ROOT" TEST_NUMBER="$test_number" TEST_RUNNER_HEADING=1 \
            sh "$test_script" >"$output_file" 2>&1 9>"$narrative_file" </dev/null &
    fi
    child=$!
    # Stream the curated narrative by default, or the full raw output in verbose.
    if [ "$VERBOSE" -eq 1 ]; then
        stream_file=$output_file
    else
        stream_file=$narrative_file
    fi
    last_size=0
    STREAM_PRINTED_LINES=0
    quiet_since=$(date +%s)
    while kill -0 "$child" 2>/dev/null; do
        sleep 1
        now=$(date +%s)
        # Watch the raw output for progress so a long Git operation that emits no
        # narrative is not mistaken for a hang.
        size=$(wc -c <"$output_file" 2>/dev/null || printf '0')
        size=$(printf '%s' "$size" | tr -d ' ')
        stream_new_output "$stream_file"
        if [ "$size" -ne "$last_size" ]; then
            last_size=$size
            quiet_since=$now
        elif [ $((now - quiet_since)) -gt "$TEST_WATCHDOG_SECONDS" ]; then
            kill "$child" 2>/dev/null || true
            wait "$child" 2>/dev/null || true
            printf 'Error: test produced no output for more than %s seconds; treating as hung\n' "$TEST_WATCHDOG_SECONDS" >>"$stream_file"
            stream_new_output "$stream_file"
            return 124
        fi
    done
    set +e
    wait "$child"
    rc=$?
    set -e
    stream_new_output "$stream_file"
    return "$rc"
}

# Run the selected tests. Kept as a function so the caller can optionally tee its
# combined output to a log file while still propagating the pass/fail status.
run_suite() {
    suite_started=$(date +%s)
    {
        printf '# git-nest Test Result\n\n'
        printf '%s\n' "- Test root: \`$TEST_ROOT\`"
        printf '%s\n\n' "- Started: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`"
        printf '%s\n\n' "- No-output watchdog: \`${TEST_WATCHDOG_SECONDS}s\`"
        printf '| ID | Test | Status | Time | Log |\n'
        printf '| --- | --- | --- | ---: | --- |\n'
    } >"$SUMMARY_MD"

    results="$TEST_ROOT/.run-all-results"
    : >"$results"
    passed=0
    failed=0
    skipped=0
    hung=0
    stop_now=0

    # Run each selected integration test in a deterministic shell environment.
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        test_number=$(id_of "$t")
        test_name=$(name_of "$t")
        heading="TEST $test_number $test_name"
        output="$TEST_ROOT/.run-all-$test_number.out"
        narrative="$TEST_ROOT/.run-all-$test_number.narrative"

        printf '\n%s\n' "$heading"
        underline_for "$heading"

        start=$(date +%s)
        if run_test_with_watchdog "$t" "$output" "$narrative"; then
            status=PASS
            if grep '^SKIP ' "$output" >/dev/null 2>&1; then
                status=SKIP
            fi
        else
            rc=$?
            status=FAIL
            if [ "$rc" -eq 124 ]; then
                hung=$((hung + 1))
                stop_now=1
            fi
            [ "$STOP_ON_FAIL" -eq 0 ] || stop_now=1
            # In the curated (non-verbose) view, print the full raw output of a
            # failing test so the failure detail is visible without rerunning.
            if [ "$VERBOSE" -eq 0 ]; then
                printf -- '--- full output: %s %s ---\n' "$test_number" "$test_name"
                cat "$output"
                printf -- '--- end output: %s %s ---\n' "$test_number" "$test_name"
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
        [ "$stop_now" -eq 0 ] || break
    done <"$SELECTED_FILE"

    total=$((passed + failed + skipped))
    suite_finished=$(date +%s)
    suite_elapsed=$((suite_finished - suite_started))
    printf '\nTest Summary\n'
    printf '%s\n' '------------'
    # Size each column to the widest actual value (including its header) so long
    # test names line up instead of overflowing a fixed width.
    sw_id=$(awk -F'|' 'BEGIN{w=length("ID")} {if(length($1)>w)w=length($1)} END{print w}' "$results")
    sw_name=$(awk -F'|' 'BEGIN{w=length("Test")} {if(length($2)>w)w=length($2)} END{print w}' "$results")
    sw_status=$(awk -F'|' 'BEGIN{w=length("Status")} {if(length($3)>w)w=length($3)} END{print w}' "$results")
    sw_time=$(awk -F'|' 'BEGIN{w=length("Time")} {if(length($4)>w)w=length($4)} END{print w}' "$results")
    # Embed the computed widths into the format string; data stays in arguments.
    summary_fmt="| %-${sw_id}s | %-${sw_name}s | %-${sw_status}s | %${sw_time}s |\n"
    printf "$summary_fmt" "ID" "Test" "Status" "Time"
    printf "$summary_fmt" "$(summary_dashes "$sw_id")" "$(summary_dashes "$sw_name")" "$(summary_dashes "$sw_status")" "$(summary_dashes "$sw_time")"
    while IFS='|' read -r number name status time; do
        printf "$summary_fmt" "$number" "$name" "$status" "$time"
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
}

if [ -n "$LOG_FILE" ]; then
    status_file=$(mktemp 2>/dev/null || printf '%s' "$TEST_ROOT/.run-all-exit")
    {
        run_rc=0
        run_suite || run_rc=$?
        printf '%s' "$run_rc" >"$status_file"
    } 2>&1 | tee "$LOG_FILE"
    rc=$(cat "$status_file" 2>/dev/null || printf '1')
    rm -f "$status_file" 2>/dev/null || true
    printf 'Full run log written to %s\n' "$LOG_FILE"
    exit "$rc"
fi

rc=0
run_suite || rc=$?
exit "$rc"
