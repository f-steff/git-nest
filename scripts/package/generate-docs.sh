#!/bin/sh
#
# generate-docs.sh -- convert git-nest documentation into man pages and
# HTML for distribution packages. Canonical converter is the pinned Docker
# image pandoc/core:3.10; the local pandoc binary is an optional fallback
# for quick iteration. If neither is available, the step is skipped with a
# warning (the assemble script still ships raw docs/).
#
# Usage:
#   sh scripts/package/generate-docs.sh [--out DIR]
#
#   --out DIR   Write man pages to DIR/man/man1 and DIR/man/man5, and HTML
#               to DIR/html (default: ./dist/docs).
#
# Man page name/section mapping (see the package-content plan):
#   README.md                          -> git-nest.1
#   docs/command-behavior-contract.md  -> git-nest-contract.1
#   docs/examples.md                   -> git-nest-examples.1
#   docs/howto.md                      -> git-nest-howto.1
#   docs/technical_docs.md             -> git-nest-technical.1
#   docs/manifest.md                   -> git-nest-manifest.5
#   docs/exit-codes.md                 -> git-nest-exit-codes.5
#   SECURITY.md                        -> git-nest-security.5
#
# Maintainer-only docs (maintainer.md, ci_and_dockerized_testing.md,
# posix_compatibility_testing.md, posix_skill_improvements.md) are NOT
# converted; they do not ship in packages.

set -eu

PANDOC_IMAGE=pandoc/core:3.10

out=dist/docs
while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            [ $# -ge 2 ] || { echo "generate-docs.sh: --out needs a directory" >&2; exit 2; }
            out=$2
            shift 2
            ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "generate-docs.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# Resolve the pandoc invocation: Docker image first, local binary second.
# The Docker mount covers only the repo, so intermediate output goes to a
# temp dir inside the repo and is moved to $out afterwards.
workdir="$repo/.docs-gen.$$"
mkdir -p "$workdir"

if docker run --rm "$PANDOC_IMAGE" --version >/dev/null 2>&1; then
    run_pandoc() {
        # $1 = output file name, $2 = extra pandoc args, rest = input files.
        _name=$1; shift
        MSYS2_ARG_CONV_EXCL="*" MSYS_NO_PATHCONV=1 docker run --rm \
            -v "$(cygpath -w "$repo" 2>/dev/null || echo "/$repo"):/work" -w /work \
            "$PANDOC_IMAGE" "$@" -o "/work/.docs-gen.$$/$_name"
    }
    pandoc_src="docker:$PANDOC_IMAGE"
elif command -v pandoc >/dev/null 2>&1; then
    run_pandoc() {
        _name=$1; shift
        pandoc "$@" -o "$workdir/$_name"
    }
    pandoc_src="local:$(pandoc --version 2>/dev/null | head -n1)"
else
    echo "generate-docs.sh: no pandoc available (tried $PANDOC_IMAGE and local); skipping man/HTML generation" >&2
    rm -rf "$workdir"
    exit 0
fi

echo "generate-docs.sh: using $pandoc_src"

man1_dir="$out/man/man1"
man5_dir="$out/man/man5"
html_dir="$out/html"
mkdir -p "$man1_dir" "$man5_dir" "$html_dir"

cd "$repo"

# name:section:input
# Only user-targeted docs ship. technical_docs.md (implementation
# architecture) and the maintainer/CI docs stay out of packages.
docs="
git-nest:1:README.md
git-nest-contract:1:docs/command-behavior-contract.md
git-nest-examples:1:docs/examples.md
git-nest-howto:1:docs/howto.md
git-nest-manifest:5:docs/manifest.md
git-nest-exit-codes:5:docs/exit-codes.md
git-nest-security:5:SECURITY.md
"

for entry in $docs; do
    name=$(echo "$entry" | cut -d: -f1)
    section=$(echo "$entry" | cut -d: -f2)
    input=$(echo "$entry" | cut -d: -f3)
    case "$section" in
        1) man_dir=$man1_dir ;;
        5) man_dir=$man5_dir ;;
    esac
    run_pandoc "$name.$section" --standalone --to man --metadata section="$section" "$input"
    # Normalize to LF (local pandoc on Windows emits CRLF; Docker emits LF).
    sed -i 's/\r$//' "$workdir/$name.$section"
    cp "$workdir/$name.$section" "$man_dir/$name.$section"
    echo "  generated $man_dir/$name.$section"
    run_pandoc "$name.html" --standalone "$input"
    sed -i 's/\r$//' "$workdir/$name.html"
    cp "$workdir/$name.html" "$html_dir/$name.html"
    echo "  generated $html_dir/$name.html"
done

rm -rf "$workdir"

# Generate a simple site index linking every HTML page, so the HTML output
# doubles as the GitHub Pages site content (see the package-content plan).
# The start page shows the CI status badges (default-branch state; the
# Pages site is the official release surface, so main is the right branch).
index="$html_dir/index.html"
{
    echo '<!DOCTYPE html>'
    echo '<html><head><meta charset="utf-8">'
    echo "<title>git-nest documentation</title>"
    echo '<style>body{font-family:sans-serif;max-width:52em;margin:2em auto;padding:0 1em;line-height:1.5}li{margin:.4em 0}</style>'
    echo '</head><body>'
    echo '<h1>git-nest documentation</h1>'
    echo '<p>'
    for badge in \
        "ci-linux-fast.yml|CI (Linux fast)" \
        "ci-linux.yml|CI (Linux)" \
        "ci-macos-fast.yml|CI (macOS fast)" \
        "ci-macos.yml|CI (macOS)" \
        "ci-windows-fast.yml|CI (Windows fast)" \
        "ci-windows.yml|CI (Windows)"; do
        wf=$(echo "$badge" | cut -d'|' -f1)
        label=$(echo "$badge" | cut -d'|' -f2)
        echo "<img src=\"https://github.com/f-steff/git-nest/actions/workflows/$wf/badge.svg\" alt=\"$label\">"
    done
    echo '</p>'
    echo '<ul>'
    for f in "$html_dir"/*.html; do
        [ "$(basename "$f")" = "index.html" ] && continue
        name=$(basename "$f" .html)
        echo "<li><a href=\"$(basename "$f")\">$name</a></li>"
    done
    echo '</ul></body></html>'
} >"$index"

echo "generate-docs.sh: man pages in $out/man, HTML in $out/html (index: $index)"
