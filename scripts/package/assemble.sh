#!/bin/sh
#
# assemble.sh -- build the git-nest release staging tree and the
# distribution artifacts.
#
# One universal package holds every file (all launchers, man pages, raw
# markdown, HTML site, skill, and all installers). The per-platform
# installers copy only the files relevant to their system:
#   git-nest-install.sh      -> git-nest, git_nest.sh, lib/,
#                               git-nest-install/uninstall.sh,
#                               man pages, md + html docs, skill
#   git-nest-install.bat     -> git-nest.bat, git-nest.ps1, git_nest.sh,
#                               lib/, git-nest-install/uninstall.bat,
#                               md + html docs, skill (the launchers
#                               forward straight to git_nest.sh, which
#                               self-dispatches -- git-nest is not needed)
#   git-nest-install.ps1     -> git-nest, git-nest.ps1, git_nest.sh, lib/,
#                               git-nest-install/uninstall.ps1,
#                               man pages, md + html docs, skill
#                               (cross-platform PowerShell installer)
#
# Artifacts:
#   git-nest-<v>.tar.gz         universal (POSIX-readable)
#   git-nest-<v>.zip            universal (Windows-readable)
#   SHA256SUMS
#
# The Windows .bat/.ps1 launchers forward directly to git_nest.sh, which
# self-dispatches when run directly (see the guard at the bottom of
# bin/git_nest.sh).
#
# Usage:
#   sh scripts/package/assemble.sh [--out DIR]
#
#   --out DIR    Write artifacts to DIR (default: ./dist).
#
# Dependencies: tar, zip (optional; falls back to python3), Docker (for
# the pandoc man/HTML step).

set -eu

out=dist

while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            [ $# -ge 2 ] || { echo "assemble.sh: --out needs a directory" >&2; exit 2; }
            out=$2
            shift 2
            ;;
        -h|--help)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "assemble.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
version=$(sed -n 's/^GIT_NEST_VERSION=//p' "$repo/bin/git_nest.sh" | head -n 1)
[ -n "$version" ] || { echo "assemble.sh: cannot read GIT_NEST_VERSION" >&2; exit 1; }

echo "assemble.sh: assembling git-nest $version"
mkdir -p "$out"

# Shared docs: shipping raw markdown set.
ship_docs_md() {
    dst=$1
    cp "$repo/LICENSE" "$repo/README.md" "$repo/SECURITY.md" "$repo/version.md" "$dst/"
    # Only user-targeted docs ship; technical_docs.md (implementation
    # architecture) and maintainer/CI docs stay out of packages.
    for f in command-behavior-contract.md ci-consumer-guide.md examples.md \
             exit-codes.md howto.md manifest.md; do
        cp "$repo/docs/$f" "$dst/"
    done
}

# ---------------------------------------------------------------------------
# Universal package (tar.gz + zip)
# ---------------------------------------------------------------------------
stage="$out/stage-universal"
rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/share/man/man1" "$stage/share/man/man5" \
    "$stage/share/doc/git-nest/html" "$stage/share/git-nest/skill"

# Full bin/: every launcher + installers.
cp "$repo/bin/git-nest" "$repo/bin/git-nest.bat" "$repo/bin/git-nest.ps1" \
    "$repo/bin/git_nest.sh" "$repo/bin/git-nest-install.sh" \
    "$repo/bin/git-nest-install.bat" "$repo/bin/git-nest-install.ps1" \
    "$repo/bin/git-nest-uninstall.sh" "$repo/bin/git-nest-uninstall.bat" \
    "$repo/bin/git-nest-uninstall.ps1" "$stage/bin/"
cp -R "$repo/bin/lib" "$stage/bin/"

# Docs: raw md (shipping set), man pages, HTML, skill.
ship_docs_md "$stage/share/doc/git-nest"
cp -R "$repo/skills/git-nest/." "$stage/share/git-nest/skill/"

if sh "$repo/scripts/package/generate-docs.sh" --out "$stage/share/doc/git-nest" >/dev/null 2>&1; then
    cp -R "$stage/share/doc/git-nest/man/." "$stage/share/man/"
    rm -rf "$stage/share/doc/git-nest/man"
    # generate-docs writes HTML into $out/html; keep it there.
else
    echo "assemble.sh: WARNING - man/HTML generation skipped (no pandoc/Docker)" >&2
fi

tar -czf "$out/git-nest-$version.tar.gz" -C "$stage" .
echo "assemble.sh: wrote $out/git-nest-$version.tar.gz"

if command -v zip >/dev/null 2>&1; then
    (cd "$stage" && zip -qr "$repo/$out/git-nest-$version.zip" .)
else
    python3 - "$out" "$version" "$stage" <<'PY'
import os, sys, zipfile
out, version, stage = sys.argv[1], sys.argv[2], sys.argv[3]
zpath = os.path.join(out, f"git-nest-{version}.zip")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(stage):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, stage))
print(f"assemble.sh: wrote {zpath}")
PY
fi
echo "assemble.sh: wrote $out/git-nest-$version.zip"
rm -rf "$stage"

# ---------------------------------------------------------------------------
# Checksums over the artifacts.
# ---------------------------------------------------------------------------
(
    cd "$out"
    sha256sum git-nest-$version.tar.gz git-nest-$version.zip 2>/dev/null > SHA256SUMS
)
echo "assemble.sh: SHA256SUMS written to $out/SHA256SUMS"
