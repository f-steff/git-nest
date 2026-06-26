#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GIT_STACK="$REPO_ROOT/bin/git-stack"
TEST_ROOT=${TEST_ROOT:-"${TMPDIR:-/tmp}/git-stack-test-workspaces"}

# Keep test output deterministic regardless of a developer's global Git config.
# The overrides also apply to repositories cloned during tests.
GIT_CONFIG_COUNT=4
GIT_CONFIG_KEY_0=core.autocrlf
GIT_CONFIG_VALUE_0=false
GIT_CONFIG_KEY_1=core.eol
GIT_CONFIG_VALUE_1=lf
GIT_CONFIG_KEY_2=core.safecrlf
GIT_CONFIG_VALUE_2=false
GIT_CONFIG_KEY_3=advice.detachedHead
GIT_CONFIG_VALUE_3=false
export GIT_CONFIG_COUNT
export GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
export GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
export GIT_CONFIG_KEY_2 GIT_CONFIG_VALUE_2
export GIT_CONFIG_KEY_3 GIT_CONFIG_VALUE_3

# Print a stable test identity for both full-suite and individual runs.
test_begin() {
    name=$1
    [ "${TEST_RUNNER_HEADING:-0}" = 1 ] && return 0
    number=${TEST_NUMBER:-00}
    printf 'TEST %s %s\n' "$number" "$name"
}

# Allocate a numbered persistent workspace for one test.
test_workspace() {
    name=$1
    number=${TEST_NUMBER:-00}
    work="$TEST_ROOT/test_${number}_$name"
    case "$work" in
        "$TEST_ROOT"/test_*) ;;
        *) echo "Refusing to use workspace outside test root: $work" >&2; exit 1 ;;
    esac
    mkdir -p "$work"
    printf '%s\n' "$work"
}

# Configure commit identity for local repositories created by tests.
git_config() {
    git config user.name "git-stack test"
    git config user.email "git-stack@example.invalid"
    git config core.autocrlf false
    git config core.eol lf
    git config core.safecrlf false
    git config advice.detachedHead false
}

# Create a normal repository on main, tolerating older Git without init -b.
make_repo() {
    dir=$1
    mkdir -p "$dir"
    git -C "$dir" init -b main >/dev/null 2>&1 || {
        git -C "$dir" init >/dev/null
        git -C "$dir" checkout -b main >/dev/null
    }
    (cd "$dir" && git_config)
}

# Create a bare remote seeded with one initial commit on main.
make_bare_remote() {
    remote=$1
    work=$2
    make_repo "$work"
    printf 'initial\n' >"$work/file.txt"
    git -C "$work" add file.txt
    git -C "$work" commit -m "initial" >/dev/null
    git -C "$work" init --bare --initial-branch=main "$remote" >/dev/null 2>&1 || git -C "$work" init --bare "$remote" >/dev/null
    git -C "$work" remote add origin "$remote"
    git -C "$work" push -u origin main >/dev/null
    git -C "$remote" symbolic-ref HEAD refs/heads/main
}

# Assert that a file contains literal text; tests use this for manifest checks.
assert_file_contains() {
    file=$1
    text=$2
    grep -F -- "$text" "$file" >/dev/null || {
        printf 'Expected %s to contain: %s\n' "$file" "$text" >&2
        exit 1
    }
}

# Assert that a file does not contain literal text.
assert_file_not_contains() {
    file=$1
    text=$2
    if grep -F -- "$text" "$file" >/dev/null; then
        printf 'Expected %s not to contain: %s\n' "$file" "$text" >&2
        exit 1
    fi
}
