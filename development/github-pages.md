# GitHub Pages Setup

The project documentation site lives at
`https://f-steff.github.io/git-nest` and is built from the repository
itself: the user-facing markdown (README.md + docs/) is rendered with the
Jekyll theme `just-the-docs`, giving the site a sidebar navigation, search,
and a dark mode that follows the visitor's OS preference.

## How It Works

- `_config.yml` (repo root) declares the `just-the-docs` remote theme,
  the site title/description, and the `exclude` list. Only user-facing
  content ships: `development/`, `tests/`, `bin/`, `scripts/`, and the
  root scratch files are excluded from the rendered site.
- The committed markdown files carry NO YAML front matter -- they are
  pure markdown, so GitHub.com renders them cleanly (front matter would
  show up as a visible table in the file view). Jekyll needs front matter
  to convert a file into a page, so `scripts/package/site-prep.sh`
  copies the user-facing markdown (index.md, README.md, SECURITY.md,
  docs/*.md) into `_site-src/` and prepends `layout:`, `title:`, and
  `nav_order:` there. The site is built from `_site-src`; the committed
  files stay untouched. Adding a page = add the markdown file + one
  `prepend_fm` line in site-prep.sh.
- `index.md` is the landing page (`layout: home`): it inlines the logo
  SVG, shows the six CI status badges, and links the manual.
- `assets/logo.svg` is the logo: the ASCII mark `\_oOO_//` as monospace
  text centered in a rounded rectangle, roughly one character of border
  on every side. The background and text colors invert via a
  `prefers-color-scheme` media query inside the SVG, so light and dark
  mode both get a contrasting badge. The same file is used as the site
  favicon via `_includes/head_custom.html`.
- `.github/workflows/pages.yml` deploys the site:
  1. `actions/configure-pages` prepares the Pages environment.
  2. `sh scripts/package/site-prep.sh` stages the site source with the
     front matter injected.
  3. Jekyll builds the site inside the `jekyll/jekyll:pages` Docker
     image (the same gem set GitHub Pages uses).
  4. `actions/upload-pages-artifact` + `actions/deploy-pages` publish it.
- The workflow is `workflow_dispatch` (manual) and reusable
  (`workflow_call`) so the release workflow can refresh the site after a
  release. Note: GitHub only allows dispatching workflows that exist on
  the default branch, so pages.yml can be run manually once it lands on
  main.

## Enabling Pages (one time, in repo Settings)

1. Repo Settings -> Pages -> Source: "GitHub Actions".
2. Run the Pages workflow manually once (Actions -> Pages -> Run
   workflow). The site appears at
   `https://f-steff.github.io/git-nest`.

## Building And Checking Locally

The GitHub Pages build environment is reproducible in Docker:

```sh
sh scripts/package/site-prep.sh
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$PWD:/srv/jekyll" -w /srv/jekyll \
  jekyll/jekyll:pages jekyll build --source _site-src --destination _site
```

The rendered site lands in `_site/` (remove `_site/` and `_site-src/`
afterwards; both are gitignored). `jekyll/jekyll:pages` is the same gem
set GitHub Pages uses.

### Previewing locally in a browser

The site is built with `baseurl: /git-nest`, so plain `python -m
http.server` will not resolve the links. Serve the built site with the
included preview server, which strips the `/git-nest` prefix:

```sh
python3 tools/serve-site.py 4000
# open http://localhost:4000/git-nest/
```

This is the branch-only way to validate a Pages change before merging:
the `github-pages` deployment environment only allows deployments from
`main` (custom branch policy), so a workflow_dispatch from another branch
builds but cannot deploy.

## Adding A Page

1. Add the markdown file under the site source set: README.md, SECURITY.md,
   index.md, or docs/ for user-facing content.
2. Register it in `scripts/package/site-prep.sh` with one `prepend_fm`
   line carrying its title and nav order (1 = Home via index.md, then the
   manual, then the docs).
3. Keep the content ASCII-only (the static analysis suite enforces this).
4. Rebuild locally with the commands above and check the new page.

## Why Not The Pandoc-HTML Approach

Earlier versions of the Pages workflow deployed the pandoc-generated HTML
from `scripts/package/generate-docs.sh`. That converter still exists and
is still the source of the man pages and offline HTML shipped inside the
release tarball; the *site* now uses Jekyll instead, because it gives
navigation, search, theming, and dark mode for free. The two pipelines are
independent: the release package and the website are no longer required to
share byte-identical HTML.
