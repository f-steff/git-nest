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
- Every rendered page carries YAML front matter with `layout: default`,
  `title:`, and `nav_order:` so the sidebar is ordered and readable.
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
  2. `actions/jekyll-build-pages` builds the site (this is the same
     GitHub Pages build environment that renders markdown on GitHub).
  3. `actions/upload-pages-artifact` + `actions/deploy-pages` publish it.
- The workflow is `workflow_dispatch` (manual) and reusable
  (`workflow_call`) so the release workflow can refresh the site after a
  release.

## Enabling Pages (one time, in repo Settings)

1. Repo Settings -> Pages -> Source: "GitHub Actions".
2. Run the Pages workflow manually once (Actions -> Pages -> Run
   workflow). The site appears at
   `https://f-steff.github.io/git-nest`.

## Building And Checking Locally

The GitHub Pages build environment is reproducible in Docker:

```sh
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$PWD:/srv/jekyll" -w /srv/jekyll \
  jekyll/jekyll:pages jekyll build
```

The rendered site lands in `_site/` (remove it afterwards; it is not
committed). `jekyll/jekyll:pages` is the same gem set GitHub Pages uses.

## Adding A Page

1. Add or edit the markdown file under the site source (README.md, or
   docs/ for user-facing content).
2. Give it front matter: `layout: default`, a `title:`, and a
   `nav_order:` (1 = Home via index.md, then the manual, then the docs).
3. Keep the content ASCII-only (the static analysis suite enforces this).
4. Rebuild locally with the Docker command above and check the new page.

## Why Not The Pandoc-HTML Approach

Earlier versions of the Pages workflow deployed the pandoc-generated HTML
from `scripts/package/generate-docs.sh`. That converter still exists and
is still the source of the man pages and offline HTML shipped inside the
release tarball; the *site* now uses Jekyll instead, because it gives
navigation, search, theming, and dark mode for free. The two pipelines are
independent: the release package and the website are no longer required to
share byte-identical HTML.
