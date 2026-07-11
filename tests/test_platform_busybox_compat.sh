#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin platform_busybox_compat

test_step "Exercise platform busybox compat" "This test verifies the documented platform busybox compat behavior and fails if command output or repository state differs from the expected result."

busybox=${BUSYBOX_EXE:-C:/busybox/bin/busybox.exe}
if [ ! -x "$busybox" ]; then
    busybox=/c/busybox/bin/busybox.exe
fi

if [ ! -x "$busybox" ]; then
    echo "SKIP BusyBox compatibility: set BUSYBOX_EXE or install C:\\busybox\\bin\\busybox.exe"
    exit 0
fi

to_windows_path() {
    path=$1
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$path"
    else
        printf '%s\n' "$path"
    fi
}

root=$(test_workspace platform_busybox_compat)
outer="$root/outer"
mkdir -p "$outer"

script=$(to_windows_path "$GIT_NEST")
outer_dir=$(to_windows_path "$outer")

# Run the real entrypoint under BusyBox sh. This verifies the script remains
# parseable and usable in a smaller shell while using a minimal scratch project.
"$busybox" sh -c '
    set -eu
    cd "$1"
    expected_version="git-nest 0.8.1 \\\\_oOO_//"
    test "$("$2" version)" = "$expected_version"
    "$2" --help >/dev/null
    "$2" init >/dev/null
    test -f .gitnest
    test ! -f .gitnest-rc
    test -f .gitignore
    "$2" repair --rc >/dev/null
    test -f .gitnest-rc
' busybox-test "$outer_dir" "$script"

describe_result "The platform busybox compat behavior matched the expected command output and repository state."
