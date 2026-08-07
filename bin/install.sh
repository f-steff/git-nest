#!/bin/sh
#
# git-nest installer -- install git-nest from a release tarball or a local
# checkout into a user-local prefix. Works on Linux, macOS, and Windows
# (Git Bash). CI agents can run this in any pipeline; the tool is plain
# shell, so there is no build step.
#
# Usage:
#   sh install.sh [--prefix DIR] [--from PATH] [--add-path]
#
#   --prefix DIR   Install under DIR (default: $HOME/.local).
#                  The bin/ payload is installed to DIR/bin and that is the
#                  only directory that needs to be on PATH.
#   --from PATH    Source: a release tarball (.tar.gz) or a directory
#                  containing bin/ (default: the checkout this script
#                  lives in, i.e. install from the repo itself).
#   --add-path     Permanently add DIR/bin to PATH by appending an export
#                  to the user's shell startup file (~/.profile, ~/.bashrc,
#                  or ~/.zshrc depending on the login shell). Default is to
#                  only print the export line; CI should NOT use --add-path.
#
# To remove the installation, run bin/uninstall.sh with the same --prefix.
#
# After install, add DIR/bin to PATH:
#   export PATH="$HOME/.local/bin:$PATH"
#
# The payload mirrors the repository's bin/ layout: git-nest, git_nest.sh,
# git-nest.bat, git-nest.ps1, and lib/ all stay in one directory, because
# the launchers resolve git_nest.sh and lib/ relative to their own
# location. Do not split or symlink them.

set -eu

prefix=${HOME:-~}/.local
from=
add_path=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "install.sh: --prefix needs a directory" >&2; exit 2; }
            prefix=$2
            shift 2
            ;;
        --from)
            [ $# -ge 2 ] || { echo "install.sh: --from needs a path" >&2; exit 2; }
            from=$2
            shift 2
            ;;
        --add-path)
            add_path=1
            shift
            ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "install.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

if [ -z "$from" ]; then
    # Default: this script's own checkout (bin/ sits next to install.sh).
    from=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fi

echo "Installing git-nest to $prefix"

# Resolve the payload (bin/ directory) from the source.
work=$(mktemp -d "${TMPDIR:-/tmp}/gitnest-install.XXXXXX")
trap 'rm -rf "$work"' EXIT

if [ -d "$from" ]; then
    # Local checkout: copy bin/ as-is.
    mkdir -p "$work/payload"
    cp -R "$from/bin/." "$work/payload/"
else
    # Tarball: two formats are accepted.
    #  - the full release staging tree (bin/ at the top level), or
    #  - the legacy bare payload tarball (contents of bin/ at the top).
    tar -xzf "$from" -C "$work"
    if [ -d "$work/bin" ]; then
        mkdir -p "$work/payload"
        cp -R "$work/bin/." "$work/payload/"
        # Preserve the docs/man/skill content for staged installs.
        if [ -d "$work/share" ]; then
            mkdir -p "$work/staged"
            cp -R "$work/share" "$work/staged/"
        fi
    else
        mkdir -p "$work/payload"
        mv "$work"/* "$work/payload/" 2>/dev/null || true
    fi
fi

[ -f "$work/payload/git-nest" ] || {
    echo "install.sh: source does not contain bin/git-nest" >&2
    exit 1
}

# Version comes from the payload itself (single source of truth).
version=$(sed -n 's/^GIT_NEST_VERSION=//p' "$work/payload/git_nest.sh" | head -n 1)
[ -n "$version" ] || version=unknown

dest="$prefix/bin"
mkdir -p "$dest"

# Clear any previous install so stale files cannot linger, then copy the
# POSIX-relevant payload. Windows-only launchers (.bat/.ps1) are skipped;
# git-nest, git_nest.sh, lib/, and the install/uninstall scripts are kept.
rm -rf "$dest"
mkdir -p "$dest"
cp "$work/payload/git-nest" "$work/payload/git_nest.sh" "$dest/"
[ -f "$work/payload/install.sh" ] && cp "$work/payload/install.sh" "$dest/"
[ -f "$work/payload/uninstall.sh" ] && cp "$work/payload/uninstall.sh" "$dest/"
cp -R "$work/payload/lib" "$dest/"

# Staged content for full-tree tarballs: man pages, docs, skill. The
# AmigaGuide (.guide) docs are Amiga-only and are not installed here.
if [ -d "$work/staged/share" ]; then
    mkdir -p "$prefix/share/man" "$prefix/share/doc" "$prefix/share/git-nest"
    if [ -d "$work/staged/share/man" ]; then
        cp -R "$work/staged/share/man/." "$prefix/share/man/"
    fi
    if [ -d "$work/staged/share/doc/git-nest" ]; then
        mkdir -p "$prefix/share/doc/git-nest"
        # Copy the shipping markdown and HTML, skip the Amiga guide dir.
        for f in "$work/staged/share/doc/git-nest"/*; do
            case "$(basename "$f")" in
                guide) continue ;;
            esac
            cp -R "$f" "$prefix/share/doc/git-nest/"
        done
    fi
    if [ -d "$work/staged/share/git-nest/skill" ]; then
        cp -R "$work/staged/share/git-nest/skill/." "$prefix/share/git-nest/skill/"
    fi
fi

echo "Installed git-nest $version"
echo "  payload: $dest"

if [ "$add_path" -eq 1 ]; then
    # Pick the shell startup file: zsh -> ~/.zshrc, bash -> ~/.bashrc,
    # otherwise the POSIX login profile ~/.profile.
    case "${SHELL:-}" in
        *zsh)   rc_file=${HOME:-~}/.zshrc ;;
        *bash)  rc_file=${HOME:-~}/.bashrc ;;
        *)      rc_file=${HOME:-~}/.profile ;;
    esac
    line="export PATH=\"$dest:\$PATH\""
    if [ -f "$rc_file" ] && grep -qF "git-nest" "$rc_file" 2>/dev/null; then
        echo "  PATH already configured in $rc_file (skipping)"
    else
        printf '\n# git-nest\nexport PATH="%s:$PATH"\n' "$dest" >>"$rc_file"
        echo "  added PATH export to $rc_file"
    fi
else
    echo 'Add to PATH: export PATH="'"$prefix"'/bin:$PATH"'
    echo "(re-run with --add-path to configure it permanently)"
fi
