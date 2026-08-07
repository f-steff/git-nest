#!/bin/sh
#
# git-nest uninstaller -- remove a git-nest installation made by install.sh
# and undo its PATH configuration. Works on Linux, macOS, and Windows
# (Git Bash).
#
# Usage:
#   sh uninstall.sh [--prefix DIR]
#
#   --prefix DIR   Remove the installation under DIR (default: $HOME/.local,
#                  matching install.sh's default). The payload DIR/bin and
#                  the PATH export added to the shell startup file are both
#                  removed.

set -eu

prefix=${HOME:-~}/.local

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "uninstall.sh: --prefix needs a directory" >&2; exit 2; }
            prefix=$2
            shift 2
            ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "uninstall.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

dest="$prefix/bin"

[ -f "$dest/git_nest.sh" ] || {
    echo "uninstall.sh: no git-nest installation found at $dest"
    exit 1
}

echo "Removing git-nest from $prefix"

# Remove the payload files. Everything in the bin/ payload belongs to
# git-nest, so the whole directory goes.
rm -rf "$dest"

# Remove staged content (man pages, docs, skill) if present.
rm -rf "$prefix/share"

# Remove any now-empty parent directory (the prefix itself) if it is empty.
rmdir "$prefix" 2>/dev/null || true

# Remove the PATH export we may have added to the shell startup file.
case "${SHELL:-}" in
    *zsh)   rc_file=${HOME:-~}/.zshrc ;;
    *bash)  rc_file=${HOME:-~}/.bashrc ;;
    *)      rc_file=${HOME:-~}/.profile ;;
esac
if [ -f "$rc_file" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/gitnest-uninstall.XXXXXX")
    # Drop the "# git-nest" comment line and the export line for this prefix.
    sed "/^# git-nest$/d; \|^export PATH=\"$dest:\$PATH\"\$|d" "$rc_file" >"$tmp"
    mv "$tmp" "$rc_file"
    echo "  removed PATH export from $rc_file"
fi

echo "git-nest uninstalled from $prefix"
