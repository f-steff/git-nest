#!/bin/sh
#
# git-nest uninstaller -- remove a git-nest installation and undo its PATH
# configuration. Works on Linux, macOS, and Windows (Git Bash).
#
# The uninstaller is copied into the installed bin/ directory, which is on
# PATH, so it is normally invoked directly:
#
#   git-nest-uninstall.sh                 (removes this installation)
#   git-nest-uninstall.sh --prefix DIR    (custom prefix)
#
#   --prefix DIR   Remove the installation under DIR (default: the
#                  installation this script lives in, or $HOME/.local when
#                  run from the source checkout). The payload DIR/bin, the
#                  staged content DIR/share, and the PATH export added to
#                  the shell startup file are removed. The bin/ directory
#                  is deleted by a detached cleanup job, so the running
#                  script itself is removed too.

set -eu

prefix=
self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
if [ -n "$self_dir" ] && [ -f "$self_dir/git-nest-main.sh" ] \
    && [ ! -e "$self_dir/../.git" ] && [ ! -f "$self_dir/../AGENTS.md" ]; then
    # Installed layout: this script sits in <prefix>/bin.
    prefix=$(CDPATH= cd -- "$self_dir/.." && pwd)
else
    # Source checkout or unknown location: default like the installer.
    prefix=${HOME:-~}/.local
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "git-nest-uninstall.sh: --prefix needs a directory" >&2; exit 2; }
            prefix=$2
            shift 2
            ;;
        -h|--help)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "git-nest-uninstall.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

dest="$prefix/bin"

[ -f "$dest/git-nest-main.sh" ] || {
    echo "git-nest-uninstall.sh: no git-nest installation found at $dest"
    exit 1
}

echo "Removing git-nest from $prefix"

# Remove staged content (man pages, docs, skill) if present.
rm -rf "$prefix/share"

# Remove the PATH export we may have added to the shell startup file.
case "${SHELL:-}" in
    *zsh)   rc_file=${HOME:-~}/.zshrc ;;
    *bash)  rc_file=${HOME:-~}/.bashrc ;;
    *)      rc_file=${HOME:-~}/.profile ;;
esac
if [ -f "$rc_file" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/gitnest-uninstall.XXXXXX")
    # Drop the "# git-nest" comment line, the export line for this prefix,
    # and the blank line the installer put before the block. Blanks are
    # accumulated and discarded when the block is found; elsewhere they
    # are restored verbatim. The file is only rewritten when a git-nest
    # block actually matched.
    if awk -v d="$dest" '
        /^$/ { blank++; next }
        /^# git-nest$/ { blank=0; found=1; next }
        $0 == "export PATH=\"" d ":$PATH\"" { found=1; next }
        { while (blank > 0) { print ""; blank-- }; print }
        END { if (!found) exit 1 }
    ' "$rc_file" >"$tmp"; then
        mv "$tmp" "$rc_file"
        echo "  removed PATH export from $rc_file"
    else
        rm -f "$tmp"
        echo "  no git-nest PATH export in $rc_file"
    fi
fi

echo "git-nest uninstalled from $prefix"

# Detached cleanup: the running script may live inside $dest, so the
# payload is removed by a background job shortly after this script exits.
( sleep 1; rm -rf "$dest"; rmdir "$prefix" 2>/dev/null ) &
