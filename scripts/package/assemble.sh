#!/bin/sh
#
# assemble.sh -- build the git-nest release staging tree and the
# distribution artifacts.
#
# One universal package holds every file (all launchers, man pages, raw
# markdown, HTML site, AmigaGuide docs, skill, and all installers). The
# per-platform installers copy only the files relevant to their system:
#   install.sh      -> git-nest, git_nest.sh, lib/, install/uninstall.sh,
#                      man pages, md + html docs, skill
#   install.bat     -> git-nest.bat, git-nest.ps1, git_nest.sh, lib/,
#                      install/uninstall.bat, md + html docs, skill
#                      (the launchers forward straight to git_nest.sh,
#                      which self-dispatches -- git-nest is not needed)
#   Amiga install   -> AmigaShell git-nest wrapper, git_nest.sh, lib/,
#                      AmigaGuide docs, skill
#
# Artifacts:
#   git-nest-<v>.tar.gz         universal (POSIX-readable)
#   git-nest-<v>.zip            universal (Windows-readable)
#   git-nest-<v>-amiga.lha      Amiga package (LHA, via the packaging image)
#   SHA256SUMS
#
# The Windows .bat/.ps1 launchers forward directly to git_nest.sh, which
# self-dispatches when run directly (see the guard at the bottom of
# bin/git_nest.sh).
#
# Usage:
#   sh scripts/package/assemble.sh [--out DIR] [--universal|--amiga]
#
#   --out DIR    Write artifacts to DIR (default: ./dist).
#   --universal  Build only the universal tar.gz + zip (default: all).
#   --amiga      Build only the Amiga .lha.
#
# Dependencies: tar, zip (optional; falls back to python3), Docker (for
# the pandoc man/HTML step and the packaging image with lha), and the
# bundled awk AmigaGuide converter.

set -eu

out=dist
targets="universal amiga"

while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            [ $# -ge 2 ] || { echo "assemble.sh: --out needs a directory" >&2; exit 2; }
            out=$2
            shift 2
            ;;
        --universal) targets="universal" ; shift ;;
        --amiga)     targets="amiga" ; shift ;;
        -h|--help)
            sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
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

echo "assemble.sh: assembling git-nest $version for: $targets"
mkdir -p "$out"

# Shared docs: shipping raw markdown set.
ship_docs_md() {
    dst=$1
    cp "$repo/LICENSE" "$repo/README.md" "$repo/SECURITY.md" "$repo/version.md" "$dst/"
    # Only user-targeted docs ship; technical_docs.md (implementation
    # architecture) and maintainer/CI docs stay out of packages.
    for f in command-behavior-contract.md examples.md exit-codes.md howto.md \
             manifest.md; do
        cp "$repo/docs/$f" "$dst/"
    done
}

# ---------------------------------------------------------------------------
# Universal package (tar.gz + zip)
# ---------------------------------------------------------------------------
if echo "$targets" | grep -q universal; then
    stage="$out/stage-universal"
    rm -rf "$stage"
    mkdir -p "$stage/bin" "$stage/share/man/man1" "$stage/share/man/man5" \
        "$stage/share/doc/git-nest/html" "$stage/share/git-nest/skill"

    # Full bin/: every launcher + installers.
    cp "$repo/bin/git-nest" "$repo/bin/git-nest.bat" "$repo/bin/git-nest.ps1" \
        "$repo/bin/git_nest.sh" "$repo/bin/install.sh" "$repo/bin/install.bat" \
        "$repo/bin/uninstall.sh" "$repo/bin/uninstall.bat" "$stage/bin/"
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

    # AmigaGuide docs also live in the universal package.
    guide_dir="$stage/share/doc/git-nest/guide"
    mkdir -p "$guide_dir"
    sh "$repo/scripts/package/generate-amigaguide.sh" --out "$guide_dir" >/dev/null 2>&1 \
        || echo "assemble.sh: WARNING - AmigaGuide generation failed" >&2

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
fi

# ---------------------------------------------------------------------------
# Amiga package (.lha, via the docker/packaging image with lha)
# ---------------------------------------------------------------------------
if echo "$targets" | grep -q amiga; then
    # The Alpine container only sees the repo (mounted at /repo), so the
    # Amiga stage must live under the repo; the .lha is moved to $out.
    amiga_stage="$repo/dist/stage-amiga"
    rm -rf "$amiga_stage"
    mkdir -p "$repo/dist" "$amiga_stage/bin" "$amiga_stage/share/doc/git-nest" \
        "$amiga_stage/share/git-nest/skill"

    # Amiga payload: AmigaShell wrapper, git_nest.sh, lib/, AmigaShell
    # install/uninstall scripts.
    cp "$repo/bin/git_nest.sh" "$amiga_stage/bin/"
    cp -R "$repo/bin/lib" "$amiga_stage/bin/"
    cp "$repo/packaging/amiga/git-nest" "$amiga_stage/bin/git-nest"
    cp "$repo/packaging/amiga/install" "$repo/packaging/amiga/uninstall" \
        "$repo/packaging/amiga/filter_lines" "$amiga_stage/bin/"

    # Docs: AmigaGuide + raw md + LICENSE/README/SECURITY/version + skill.
    ship_docs_md "$amiga_stage/share/doc/git-nest"
    cp -R "$repo/skills/git-nest/." "$amiga_stage/share/git-nest/skill/"
    guide_dir="$amiga_stage/share/doc/git-nest/guide"
    mkdir -p "$guide_dir"
    sh "$repo/scripts/package/generate-amigaguide.sh" --out "$guide_dir" >/dev/null 2>&1 \
        || echo "assemble.sh: WARNING - AmigaGuide generation failed" >&2

    # Create the .lha with the packaging image (lha from
    # https://github.com/jca02266/lha, baked into docker/packaging -- see
    # docker/packaging/Dockerfile). The repo is mounted read-write so the
    # archive can be written under /repo/dist.
    if ! docker image inspect git-nest-packaging >/dev/null 2>&1; then
        docker build -q -t git-nest-packaging \
            -f "$repo/docker/packaging/Dockerfile" "$repo/docker/packaging" >/dev/null
    fi
    if MSYS2_ARG_CONV_EXCL="*" MSYS_NO_PATHCONV=1 docker run --rm \
        -v "$(cygpath -w "$repo" 2>/dev/null || echo "/$repo"):/repo" -w /repo \
        git-nest-packaging sh -c "
            cd /repo/dist && rm -f 'git-nest-$version-amiga.lha'
            lha a 'git-nest-$version-amiga.lha' stage-amiga >/dev/null
        "; then
        cp "$repo/dist/git-nest-$version-amiga.lha" "$out/"
        echo "assemble.sh: wrote $out/git-nest-$version-amiga.lha"
    else
        echo "assemble.sh: ERROR - lha creation failed (Docker/packaging image unavailable?)" >&2
        exit 1
    fi
    rm -rf "$amiga_stage" "$repo/dist/git-nest-$version-amiga.lha"
fi

# ---------------------------------------------------------------------------
# Checksums over the artifacts.
# ---------------------------------------------------------------------------
(
    cd "$out"
    sha256sum git-nest-$version.tar.gz git-nest-$version.zip \
        git-nest-$version-amiga.lha 2>/dev/null > SHA256SUMS
)
echo "assemble.sh: SHA256SUMS written to $out/SHA256SUMS"
