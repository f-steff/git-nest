#!/bin/sh
#
# git-nest installer -- install git-nest from a release tarball, from a
# local checkout, or directly from GitHub. Works on Linux, macOS, BSD, and
# Windows (Git Bash). CI agents can run this in any pipeline; the tool is
# plain shell, so there is no build step.
#
# Usage:
#   sh git-nest-install.sh [--prefix DIR] [--from PATH] [--no-add-path]
#
#   --prefix DIR   Install under DIR (default: $HOME/.local).
#                  The bin/ payload is installed to DIR/bin and that is the
#                  only directory that needs to be on PATH.
#   --from PATH    Source: a release tarball (.tar.gz) or a directory
#                  containing bin/ (default: this script's checkout, or a
#                  download from GitHub when the script is piped in).
#   --no-add-path  Do NOT touch PATH. Default is to append DIR/bin to PATH
#                  permanently by adding an export to the user's shell
#                  startup file (~/.profile, ~/.bashrc, or ~/.zshrc
#                  depending on the login shell); with --no-add-path only
#                  the export line is printed. CI pipelines should pass
#                  --no-add-path (or sh -s -- --no-add-path when piped).
#   --add-path     Explicitly force the PATH append (the default).
#
# Download mode (curl | sh) -- the script fetches the release tarball
# itself when it is not run from a checkout and no --from is given:
#
#   Latest release (default):
#     curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
#
#   Pinned version:
#     VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
#
#   VERSION=latest (default) resolves the newest release via the GitHub
#   API; VERSION=x.y.z downloads that release directly. GIT_NEST_REPO
#   overrides the repository (default: f-steff/git-nest). The tarball is
#   verified against the release's SHA256SUMS when a checksum tool is
#   available.
#
# To remove the installation, run bin/git-nest-uninstall.sh with the same --prefix.
#
# The installer appends DIR/bin to PATH by default; pass --no-add-path to
# skip that and configure PATH manually:
#   export PATH="$HOME/.local/bin:$PATH"
#
# The payload mirrors the repository's bin/ layout: git-nest, git-nest-main.sh,
# git-nest.bat, git-nest.ps1, and lib/ all stay in one directory, because
# the launchers resolve git-nest-main.sh and lib/ relative to their own
# location. Do not split or symlink them.

set -eu

prefix=${HOME:-~}/.local
from=
add_path=1
fetch=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "git-nest-install.sh: --prefix needs a directory" >&2; exit 2; }
            prefix=$2
            shift 2
            ;;
        --from)
            [ $# -ge 2 ] || { echo "git-nest-install.sh: --from needs a path" >&2; exit 2; }
            from=$2
            shift 2
            ;;
        --add-path)
            add_path=1
            shift
            ;;
        --no-add-path)
            add_path=0
            shift
            ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "git-nest-install.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

if [ -z "$from" ]; then
    # Default: this script's own checkout (bin/ sits next to install.sh).
    # When the script is piped via stdin (curl | sh), $0 has no checkout,
    # so fall back to downloading the release tarball from GitHub.
    self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
    if [ -n "$self_dir" ] && [ -f "$self_dir/git-nest" ]; then
        from=$(CDPATH= cd -- "$self_dir/.." && pwd)
    else
        fetch=1
    fi
fi

echo "Installing git-nest to $prefix"

# Resolve the payload (bin/ directory) from the source.
work=$(mktemp -d "${TMPDIR:-/tmp}/gitnest-install.XXXXXX")
trap 'rm -rf "$work"' EXIT

if [ "$fetch" -eq 1 ]; then
    # Download mode: VERSION=latest (default) resolves the newest release
    # via the GitHub API; VERSION=x.y.z downloads that release directly.
    fetch_version=${VERSION:-latest}
    repo=${GIT_NEST_REPO:-f-steff/git-nest}
    if [ "$fetch_version" = "latest" ]; then
        tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
        [ -n "$tag" ] || {
            echo "git-nest-install.sh: cannot resolve the latest release via the GitHub API" >&2
            exit 1
        }
        fetch_version=${tag#v}
    fi
    url="https://github.com/$repo/releases/download/v$fetch_version/git-nest-$fetch_version.tar.gz"
    echo "Downloading $url"
    curl -fsSL -o "$work/git-nest.tar.gz" "$url" || {
        echo "git-nest-install.sh: download failed: $url" >&2
        exit 1
    }
    # Best-effort checksum verification against the release SHA256SUMS.
    if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
        if curl -fsSL -o "$work/SHA256SUMS" \
            "https://github.com/$repo/releases/download/v$fetch_version/SHA256SUMS" 2>/dev/null; then
            if command -v sha256sum >/dev/null 2>&1; then
                (cd "$work" && grep -F "git-nest-$fetch_version.tar.gz" SHA256SUMS \
                    | sha256sum -c -) || { echo "git-nest-install.sh: SHA256SUMS verification failed" >&2; exit 1; }
            else
                (cd "$work" && grep -F "git-nest-$fetch_version.tar.gz" SHA256SUMS \
                    | shasum -a 256 -c -) || { echo "git-nest-install.sh: SHA256SUMS verification failed" >&2; exit 1; }
            fi
            echo "git-nest-install.sh: tarball checksum verified"
        fi
    fi
    from="$work/git-nest.tar.gz"
fi

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
    echo "git-nest-install.sh: source does not contain bin/git-nest" >&2
    exit 1
}

# Version comes from the payload itself (single source of truth).
version=$(sed -n 's/^GIT_NEST_VERSION=//p' "$work/payload/git-nest-main.sh" | head -n 1)
[ -n "$version" ] || version=unknown

dest="$prefix/bin"
mkdir -p "$dest"

# Clear any previous install so stale files cannot linger, then copy the
# POSIX-relevant payload. Windows-only launchers (.bat/.ps1) are skipped;
# git-nest, git-nest-main.sh, lib/, and the install/uninstall scripts are kept.
rm -rf "$dest"
mkdir -p "$dest"
cp "$work/payload/git-nest" "$work/payload/git-nest-main.sh" "$dest/"
[ -f "$work/payload/git-nest-install.sh" ] && cp "$work/payload/git-nest-install.sh" "$dest/"
[ -f "$work/payload/git-nest-uninstall.sh" ] && cp "$work/payload/git-nest-uninstall.sh" "$dest/"
cp -R "$work/payload/lib" "$dest/"

# Staged content for full-tree tarballs: man pages, docs, skill.
if [ -d "$work/staged/share" ]; then
    mkdir -p "$prefix/share/man" "$prefix/share/doc" "$prefix/share/git-nest"
    if [ -d "$work/staged/share/man" ]; then
        cp -R "$work/staged/share/man/." "$prefix/share/man/"
    fi
    if [ -d "$work/staged/share/doc/git-nest" ]; then
        mkdir -p "$prefix/share/doc/git-nest"
        # Copy the shipping markdown and HTML.
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
    echo "(PATH was left untouched because --no-add-path was given)"
fi
