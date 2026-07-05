#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin busybox_compat

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

root=$(test_workspace busybox_compat)
outer="$root/outer"
mkdir -p "$outer"

script=$(to_windows_path "$GIT_LEGO")
outer_dir=$(to_windows_path "$outer")

# Run the real entrypoint under BusyBox sh. This verifies the script remains
# parseable and usable in a smaller shell while using a minimal scratch project.
"$busybox" sh -c '
    set -eu
    cd "$1"
    test "$("$2" version)" = "git-lego 0.7.0"
    "$2" --help >/dev/null
    "$2" init >/dev/null
    test -f .gitlego
    test ! -f .gitlego-rc
    test -f .gitignore
    "$2" init --rc >/dev/null
    test -f .gitlego-rc
' busybox-test "$outer_dir" "$script"
