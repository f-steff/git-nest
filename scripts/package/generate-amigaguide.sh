#!/bin/sh
#
# generate-amigaguide.sh -- convert the shipping git-nest markdown docs
# into a single AmigaGuide (.guide) hypertext database for the Amiga
# distribution package. Uses a bundled awk converter; no pandoc or Docker
# required.
#
# The output is ONE file, git-nest.guide, with a main chapter node that
# links to one node per document (AmigaGuide's idiomatic structure -- a
# database with linked nodes, not separate files).
#
# The converter handles the subset of markdown the docs use: ATX headings,
# bullet lists, numbered lists, fenced code blocks, inline code, bold,
# links, and horizontal rules. Unsupported constructs are passed through
# as plain text.
#
# Usage:
#   sh scripts/package/generate-amigaguide.sh --out DIR
#
#   --out DIR   Write git-nest.guide to DIR (default: ./dist/guide).

set -eu

out=dist/guide
while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            [ $# -ge 2 ] || { echo "generate-amigaguide.sh: --out needs a directory" >&2; exit 2; }
            out=$2
            shift 2
            ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "generate-amigaguide.sh: unknown argument: $1 (see --help)" >&2
            exit 2
            ;;
    esac
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
version=$(sed -n 's/^GIT_NEST_VERSION=//p' "$repo/bin/git_nest.sh" | head -n 1)
[ -n "$version" ] || version=unknown

mkdir -p "$out"
guide="$out/git-nest.guide"

# name|input|node-title
# Only user-targeted docs ship. technical_docs.md (implementation
# architecture) and the maintainer/CI docs stay out of packages.
docs="
git-nest|README.md|Introduction
git-nest-contract|docs/command-behavior-contract.md|Command Behavior Contract
git-nest-examples|docs/examples.md|Examples
git-nest-howto|docs/howto.md|How-To
git-nest-manifest|docs/manifest.md|Manifest Format
git-nest-exit-codes|docs/exit-codes.md|Exit Codes
git-nest-security|SECURITY.md|Security
"

cd "$repo"

# Database header + main node with a link per chapter.
{
    echo "@DATABASE git-nest.guide, VERSION $version, DATE 2026"
    echo "@AUTHOR git-nest maintainers"
    echo ""
    echo "@NODE main; git-nest $version"
    echo ""
    echo "@{\"b\" git-nest}"
    echo ""
    echo "git-nest records and restores reproducible workspaces made from"
    echo "independent Git repositories."
    echo ""
    echo "Chapters:"
    echo ""
    printf '%s\n' "$docs" | while IFS='|' read -r name input title; do
        [ -n "$name" ] || continue
        echo "@{\"$name\" $title}"
    done
    echo ""
    echo "@ENDNODE"
} >"$guide"

# One node per document.
printf '%s\n' "$docs" | while IFS='|' read -r name input title; do
    [ -n "$name" ] || continue
    {
        echo ""
        echo "@NODE \"$name\"; $title"
        echo ""
        awk '
            BEGIN { in_code = 0 }
            /^```/ {
                in_code = !in_code
                if (!in_code) printf "\n"
                next
            }
            in_code {
                printf "@{f %s}\n", $0
                next
            }
            /^# / {
                sub(/^# /, "")
                printf "@{\"b\" %s}\n\n", $0
                next
            }
            /^## / {
                sub(/^## /, "")
                printf "@{\"b\" %s}\n\n", $0
                next
            }
            /^### / {
                sub(/^### /, "")
                printf "@{\"i\" %s}\n\n", $0
                next
            }
            /^[-*] / {
                sub(/^[-*] /, "")
                printf "@{\"*\" %s}\n", $0
                next
            }
            /^[0-9]+\. / {
                sub(/^[0-9]+\. /, "")
                printf "@{\"1.\" %s}\n", $0
                next
            }
            /^---+$/ || /^===+$/ {
                printf "\n"
                next
            }
            /^$/ {
                printf "\n"
                next
            }
            {
                line = $0
                out_line = ""
                rest = line
                while (match(rest, /\[!\[[^]]*\]\([^)]*\)\]\([^)]*\)/)) {
                    out_line = out_line substr(rest, 1, RSTART - 1)
                    rest = substr(rest, RSTART + RLENGTH)
                }
                out_line = out_line rest
                line = out_line

                out_line = ""
                rest = line
                while (match(rest, /`[^`]*`/)) {
                    out_line = out_line substr(rest, 1, RSTART - 1) "@{f " substr(rest, RSTART + 1, RLENGTH - 2) "}"
                    rest = substr(rest, RSTART + RLENGTH)
                }
                out_line = out_line rest
                line = out_line

                out_line = ""
                rest = line
                while (match(rest, /\*\*[^*]*\*\*/)) {
                    out_line = out_line substr(rest, 1, RSTART - 1) "@{b " substr(rest, RSTART + 2, RLENGTH - 4) "}"
                    rest = substr(rest, RSTART + RLENGTH)
                }
                out_line = out_line rest
                line = out_line

                out_line = ""
                rest = line
                while (match(rest, /!\[[^]]*\]\([^)]*\)/)) {
                    out_line = out_line substr(rest, 1, RSTART - 1)
                    rest = substr(rest, RSTART + RLENGTH)
                }
                out_line = out_line rest
                line = out_line

                out_line = ""
                rest = line
                while (match(rest, /\[[^]]*\]\([^)]*\)/)) {
                    link = substr(rest, RSTART, RLENGTH)
                    text = link
                    sub(/\]\([^)]*\)$/, "", text)
                    sub(/^\[/, "", text)
                    out_line = out_line substr(rest, 1, RSTART - 1) text
                    rest = substr(rest, RSTART + RLENGTH)
                }
                out_line = out_line rest
                printf "%s\n", out_line
            }
        ' "$input"
        echo ""
        echo "@ENDNODE"
    } >>"$guide"
done

echo "generate-amigaguide.sh: wrote $guide ($(wc -l <"$guide") lines, $(grep -c '^@NODE ' "$guide" | tr -d ' ') nodes)"
