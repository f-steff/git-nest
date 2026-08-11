#!/bin/sh
#
# site-prep.sh -- build the Jekyll site source in _site-src/.
#
# The committed markdown files are pure markdown (no YAML front matter, so
# GitHub.com renders them cleanly). Jekyll needs front matter to convert a
# file into a page, so this script copies the user-facing markdown into
# _site-src/ and prepends the layout/title/nav_order front matter there.
# See development/github-pages.md.
#
# Usage:
#   sh scripts/package/site-prep.sh
#
# Then build the site (same gem set GitHub Pages uses):
#   docker run --rm -v "$PWD:/srv/jekyll" -w /srv/jekyll \
#     jekyll/jekyll:pages jekyll build --source _site-src --destination _site

set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
stage="$repo/_site-src"

rm -rf "$stage"
mkdir -p "$stage/docs" "$stage/assets" "$stage/_includes"

cp "$repo/_config.yml" "$stage/"
cp -R "$repo/_includes/." "$stage/_includes/"
cp -R "$repo/assets/." "$stage/assets/"
cp "$repo/index.md" "$repo/README.md" "$repo/SECURITY.md" "$stage/"
cp "$repo"/docs/*.md "$stage/docs/"

# The README's "Documentation:" line links back to the GitHub Pages site
# home. It is meant for the GitHub repository page; on the site's own
# Manual page it would link to the site itself, so it is stripped from
# the staged copy only (the committed README keeps it).
sed -i '/^Documentation: <https:\/\/f-steff\.github\.io\/git-nest\/>$/d' "$stage/README.md"

# name:section:title:nav_order -- layout is always "default" except the
# home page (index.md), which uses "home".
prepend_fm() {
    name=$1
    section=$2
    title=$3
    order=$4
    file="$stage/$name"
    [ -f "$file" ] || { echo "site-prep.sh: missing $file" >&2; exit 1; }
    tmp="$file.tmp"
    {
        echo "---"
        echo "layout: $section"
        echo "title: $title"
        echo "nav_order: $order"
        echo "---"
        cat "$file"
    } >"$tmp"
    mv "$tmp" "$file"
}

prepend_fm index.md home Home 1
prepend_fm README.md default Manual 2
prepend_fm docs/command-behavior-contract.md default "Behavior Contract" 3
prepend_fm docs/manifest.md default "Manifest Format" 4
prepend_fm docs/examples.md default Examples 5
prepend_fm docs/howto.md default How-To 6
prepend_fm docs/exit-codes.md default "Exit Codes" 7
prepend_fm SECURITY.md default "Security Policy" 8
prepend_fm docs/ci-consumer-guide.md default "CI Consumer Guide" 9

echo "site-prep.sh: staged site source in $stage"
