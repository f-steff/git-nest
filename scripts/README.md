# Scripts

Build, packaging, and local-development tooling for git-nest. All scripts
are for the release pipeline, CI, or local dev convenience - they are not
shipped in the end-user release tarball.

## package/

Release packaging and site building:

- **assemble.sh** - Builds the universal release staging tree (binaries,
  docs, man pages, skill) and creates the distribution tarball, zip, and
  SHA256SUMS.
- **generate-docs.sh** - Converts the shipping markdown docs into man pages
  and standalone HTML using the pinned Docker image pandoc/core:3.10.
- **site-prep.sh** - Stages the Jekyll site source by copying the user-facing
  markdown (README.md, docs/, docs/site/) into `_site-src/` with YAML front
  matter injected.
- **version-check.sh** - Release gate: verifies that GIT_NEST_VERSION is
  strictly newer than the last release tag.

## tools/

Local development helpers:

- **serve-site.py** - Strips the `/git-nest` baseurl prefix and serves the
  built site from `_site/` for local preview.
