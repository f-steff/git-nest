#!/bin/sh
# Test: static code analysis -- syntax, shellcheck, formatting, bashism compliance

. "$(dirname "$0")/helper.sh"
. "$(dirname "$0")/check.sh"
test_begin static-code-analysis

if [ "${GIT_NEST_SKIP_STATIC:-0}" = 1 ]; then
    test_step "Skip static analysis" "GIT_NEST_SKIP_STATIC=1 is set."
    describe_result "Static analysis skipped."
    exit 0
fi

test_step "Shell syntax (sh -n)" "Verifies every file parses without syntax errors."
check_syntax
describe_result "${FILE_COUNT} files, ${LINE_COUNT} lines: syntax OK."

skipped=0

test_step "ShellCheck" "Static analysis with ShellCheck (config: bin/.shellcheckrc)."
set +e; check_shellcheck; sc_rc=$?; set -e
case $sc_rc in
    0) describe_result "${FILE_COUNT} files, 0 warnings." ;;
    2) describe_result "ShellCheck: skipped (tool not available)."; skipped=$((skipped + 1)) ;;
    *) exit 1 ;;
esac

test_step "shfmt (formatting)" "Verifies POSIX dialect formatting is consistent."
set +e; check_shfmt; sf_rc=$?; set -e
case $sf_rc in
    0) describe_result "${FILE_COUNT} files, all formatted." ;;
    2) describe_result "shfmt: skipped (tool not available)."; skipped=$((skipped + 1)) ;;
    *) exit 1 ;;
esac

test_step "checkbashisms (POSIX compliance)" "Scans for Bash-only features that would break under dash or other strict POSIX shells."
set +e; check_bashisms; cb_rc=$?; set -e
case $cb_rc in
    0) describe_result "${FILE_COUNT} files, 0 bashisms." ;;
    2) describe_result "checkbashisms: skipped (tool not available)."; skipped=$((skipped + 1)) ;;
    *) exit 1 ;;
esac

test_step "ASCII-only (bin, tests, docs, skills, root markdown)" "Keeps all source and documentation plain ASCII (no em/en dashes, curly quotes, arrows, or box-drawing characters) so diffs and terminal rendering stay identical across editors, shells, and platforms. Uses grep only, so it never skips."
check_ascii || exit 1
describe_result "No non-ASCII characters found."

test_step "Version alignment" "GIT_NEST_VERSION in bin/git-nest-main.sh must match the newest version.md entry, so a version bump in either file always lands together."
check_version_alignment || exit 1
describe_result "GIT_NEST_VERSION matches the newest version.md entry."

test_step "Relative links in committed markdown" "Every relative link in a committed .md file must resolve to an existing file, so docs and the README never point at missing targets on any branch."
check_links || exit 1
describe_result "All relative links in committed markdown resolve to existing files."

test_step "Release version gate" "The release workflow's version gate (scripts/package/version-check.sh) must accept the current GIT_NEST_VERSION, so the CI-verified logic matches what the workflow runs."
check_version_gate || exit 1
describe_result "GIT_NEST_VERSION passes the release version gate."

if [ "$skipped" -gt 0 ]; then
    describe_result "Static analysis passed ($skipped tool(s) skipped, install with: sh tests/integration-tests/check.sh)."
else
    describe_result "All static quality checks passed."
fi
