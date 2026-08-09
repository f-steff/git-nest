# GitHub Pages For git-nest

Personal research notes. NOT committed (temp-doc/ is gitignored).

## What GitHub Pages is

Free static-site hosting for GitHub repositories:

- Per-project site at `https://<user>.github.io/<repo>/` (or a custom
  domain).
- Two deploy modes:
  1. **Branch-based** (legacy): serve a `gh-pages` branch (or `main`
     `/docs`).
  2. **Actions-based** (current recommended): a workflow builds the site
     and deploys via `actions/configure-pages` + `actions/upload-pages-
     artifact` + `actions/deploy-pages`.
- Built-in Jekyll: markdown files render automatically, with a theme and
  automatic navigation/toc; no build step needed for plain markdown.
- HTTPS by default; custom domains supported (CNAME file + DNS).
- Free; limits: 1 GB site, 100 GB/month soft bandwidth, 10 builds/hour
  for Actions-based deploys.

## What git-nest could use it for

### 1. Project documentation site (main candidate)

git-nest already has a complete markdown manual in the repo:

```
README.md                        (36 KB - the manual)
docs/command-behavior-contract.md  (the behavior contract)
docs/manifest.md                   (manifest format)
docs/examples.md                   (workflows with real output)
docs/howto.md, exit-codes.md, ...
SECURITY.md
```

A Pages site would present these as a browsable manual with a landing
page, table of contents, and per-page navigation -- nicer for first-time
visitors than browsing raw markdown. Because the repo is plain ASCII
markdown, Jekyll renders it with zero configuration and no build toolchain.

### 2. Hosting the self-hosted APT/RPM repo (secondary)

The distribution investigation noted a self-hosted APT/RPM repo could live
on GitHub Pages (static `dists/` + `pool/`). Pages serves static files, so
this works technically. However, GitHub **Releases already hosts the
tarballs** and is the primary distribution channel, so Pages-hosted
packages would be an add-on for distro users -- see
`distribution-investigation.md` for the PPA/COPR comparison.

### 3. Install/quickstart landing page (cheap)

A single `index.md` pointing at the README quickstart + release download +
installer one-liner. Almost free to maintain.

## Considerations

- **Maintenance**: the docs site duplicates content that already lives in
  the repo. Mitigation: build the site from the same `docs/` + README via
  Jekyll on every push to `main`, so it never drifts. A single workflow
  (`.github/workflows/pages.yml`) deploys the rendered site; ~20 lines.
- **Needs the repo public**: Pages works for private repos only on paid
  plans; git-nest is going public anyway (CI prerequisite already).
- **Jekyll vs plain**: Jekyll is the zero-config path and handles
  markdown; alternative is a static generator or hand-built HTML (more
  work). Jekyll's default theme is fine for a manual.
- **Domain**: `f-steff.github.io/git-nest` by default; a custom domain
  (e.g. `gitnest.dev`) is optional later.
- **Not needed for the tool itself**: git-nest is a CLI; the docs are
  already readable on GitHub. Pages is polish + discoverability, not
  functionality.

## Recommendation

**Worth doing, low priority.** A one-workflow Jekyll site serving
`README.md` + `docs/` gives the project a professional documentation URL
for little maintenance, and doubles as the APT/RPM file host if those
packages are ever added. Recommended order:

1. Enable Pages in repo Settings (Actions-based deploy).
2. Add `.github/workflows/pages.yml` building Jekyll from the repo root
   markdown (or a minimal `docs/` index), deployed on push to `main`.
3. Add a README badge/link to the site.
4. Later: custom domain; optional APT/RPM repo under the same site.

Roughly a day of work including the workflow and any Jekyll config
adjustments. Deliberately defer until after the CI workflows and the first
release are settled.
