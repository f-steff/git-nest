#!/bin/sh
#
# Shared mock system for unit tests. Provides a mock Git shim that intercepts
# all git calls and returns canned responses. Default responses cover common
# operations; individual tests can override specific responses via
# mock_git_response.
#
# ASCII only -- per project style.

# Path to the mock Git shim script.
MOCK_BIN=

# Table of mock responses. Each line is:
#   subcommand<TAB>stdout content
# Tests call mock_git_response to add entries or override defaults.
MOCK_RESPONSE_FILE=

# Default responses keyed by subcommand only (ignoring args).
# The mock always returns the first matching entry for the subcommand.
DEFAULT_MOCK_RESPONSES="
rev-parse	0123456789abcdef0123456789abcdef01234567
config	true
remote	
symbolic-ref	main
status	
ls-remote	0123456789abcdef0123456789abcdef01234567	HEAD
show-ref	
"

# Install the mock Git shim into MOCK_BIN and prepend to PATH.
install_mock_git() {
    MOCK_BIN=$(mktemp -d "${TMPDIR:-/tmp}/gn-mock-git.XXXXXX")
    MOCK_RESPONSE_FILE=$(mktemp)

    # Write default responses into the response table file.
    printf '%s\n' "$DEFAULT_MOCK_RESPONSES" | sed '/^$/d' >"$MOCK_RESPONSE_FILE"

    # Write the mock git executable.
    # Strips global flags (-C <dir>, -c <var>) before looking up the subcommand.
    cat >"$MOCK_BIN/git" <<'MOCK_GIT_SCRIPT'
#!/bin/sh
# Mock git shim -- looks up canned responses keyed by subcommand.
# Response file format: subcommand<TAB>stdout
# Returns 0 when a response is found, 1 otherwise.

# Skip global git flags (-C, -c) that appear before the subcommand.
while [ $# -gt 0 ]; do
    case "$1" in
    -C|-c) shift 2 ;;
    -c*.protocol.*) shift ;;
    *) break ;;
    esac
done

_mg_cmd=$1
shift

# Build a key with the subcommand and all remaining args, tab-separated,
# so "config --get remote.origin.promisor" becomes:
#   "config	--get	remote.origin.promisor"
# Try exact arg-match first; fall back to subcommand-only match.
_mg_key="$_mg_cmd"
for _mg_arg in "$@"; do
    _mg_key="$_mg_key	$_mg_arg"
done

# Try exact match first.
_mg_line=$(grep -F "$_mg_key	" "$MOCK_RESPONSE_FILE" 2>/dev/null | head -1)

# Fall back to subcommand-only match.
if [ -z "$_mg_line" ]; then
    _mg_line=$(grep -F "${_mg_cmd}	" "$MOCK_RESPONSE_FILE" 2>/dev/null | head -1)
fi
if [ -z "$_mg_line" ]; then
    printf 'mock git: unhandled: %s\n' "$_mg_cmd" >&2
    exit 1
fi

# Extract the stdout value (everything after the first tab).
# Extract the stdout value (last tab-separated field).
_mg_stdout=$(printf '%s' "$_mg_line" | awk -F'\t' '{print $NF}')
if [ -n "$_mg_stdout" ]; then
    printf '%s\n' "$_mg_stdout"
fi
exit 0
MOCK_GIT_SCRIPT

    chmod +x "$MOCK_BIN/git"
    PATH="$MOCK_BIN:$PATH"
    export PATH
    export MOCK_RESPONSE_FILE
    # zsh caches command paths at function definition time; after PATH is
    # modified, rehash so subsequent calls (awk, git, cksum, etc.) are found.
    hash -r 2>/dev/null || rehash 2>/dev/null || true
}

# Record (or override) a mock response for a git subcommand.
# Usage: mock_git_response "subcommand" "stdout content"
#     or: mock_git_response "subcommand" "arg1" "arg2" ... "stdout content"
# When args are provided, the mock matches the exact command line.
# With a single string, all calls to the subcommand match (catch-all).
mock_git_response() {
    _mr_cmd=$1
    if [ $# -eq 2 ]; then
        # Simple: mock_git_response "subcommand" "response"
        _mr_stdout=$2
    else
        # With args: mock_git_response "subcommand" "arg1" "arg2" ... "response"
        # Build the key from all args except the last (which is the response value).
        shift
        _mr_stdout=
        for _mr_arg in "$@"; do
            if [ -n "$_mr_stdout" ]; then
                _mr_cmd="$_mr_cmd	$_mr_stdout"
            fi
            _mr_stdout=$_mr_arg
        done
    fi
    _mr_existing=$(grep -Fv "${_mr_cmd}	" "$MOCK_RESPONSE_FILE" 2>/dev/null || true)
    {
        printf '%s\n' "$_mr_existing"
        printf '%s\t%s\n' "$_mr_cmd" "$_mr_stdout"
    } >"$MOCK_RESPONSE_FILE"
}
