# Distribution Overview

How git-nest is packaged, released, and installed. This is the
maintainer-facing companion to the user-facing `docs/ci-consumer-guide.md`.

## Strategy

git-nest is plain shell with no build step. A release artifact is simply a
tarball/zip of the payload, and the SAME artifact works on every platform
-- there are no per-OS binaries. The distribution strategy is therefore:

- **GitHub Releases** host the artifacts: a universal
  `git-nest-<version>.tar.gz` (POSIX-readable), a universal
  `git-nest-<version>.zip` (Windows-readable), and `SHA256SUMS`.
- **Install scripts** are the install path on every platform: `bin/git-nest-install.sh`
  for POSIX shells (Linux, macOS, BSD, Git Bash) and `bin/git-nest-install.ps1`
  for PowerShell. Both support `VERSION=latest` (default, resolved via
  the GitHub API) and `VERSION=x.y.z` (direct download), verify the
  download against `SHA256SUMS`, and install into a user-local prefix.
  One-liners:

  ```sh
  curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
  ```

  ```bat
  powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex }"
  ```

- **No native package managers.** We decided against Chocolatey, Homebrew,
  Scoop, Debian/APT, RPM, AUR, and Winget packages; the universal tarball
  plus install scripts covers every platform with zero external accounts,
  zero per-platform packaging code, and one artifact to verify. The
  install scripts make CI integration a one-liner on any system.

## Build Architecture

One `assemble` step produces a staging tree, then per-format steps package
it:

```
scripts/package/assemble.sh
  |-- stage/
  |   |-- bin/                  (payload: git-nest + launchers + installers)
  |   |-- share/man/            (pandoc-generated man pages)
  |   |-- share/doc/git-nest/   (raw docs/ markdown + generated HTML)
  |   `-- share/git-nest/skill/ (skills/git-nest/SKILL.md)
  |-- git-nest-<v>.tar.gz       (universal, POSIX-readable)
  |-- git-nest-<v>.zip          (universal, Windows-readable)
  `-- SHA256SUMS
```

- `assemble.sh` is pure POSIX sh. It stages the payload (`bin/`), the
  shipping markdown set (`docs/`), the AI skill, and the man/HTML output
  of `generate-docs.sh`, then creates the two archives and `SHA256SUMS`.
- `generate-docs.sh` converts the shipping markdown into man pages
  (man1/man5) and standalone HTML using the pinned Docker image
  `pandoc/core:3.10`; a local `pandoc` binary is an optional fallback, and
  the step is skipped with a warning when neither is available. Output is
  normalized to LF so local and CI builds are byte-identical.
- The version is read from `GIT_NEST_VERSION` in `bin/git-nest-main.sh` (single
  source of truth; `check_version_alignment` enforces it matches
  version.md). Release tags are `v<version>`.

## Release Pipeline

`.github/workflows/release.yml` is a manual (`workflow_dispatch`)
pipeline:

1. `test` -- run the full test suite on Linux.
2. `version-check` -- `scripts/package/version-check.sh` rejects the
   release unless the version is strictly newer than the last release
   tag.
3. `assemble` -- run `assemble.sh`, upload the artifacts.
4. `release` -- create the GitHub Release with the version.md changelog
   entry as notes, attach the tarball, zip, and SHA256SUMS.
5. `pages` -- refresh the documentation site via the reusable Pages
   workflow.

The script is installed with `curl | sh` (or `iwr | iex`), so "publish
the release" is the whole distribution step.

## Code Signing

A shell-script tool has no executable to sign; no platform requires a
signature on `.sh`/`.ps1` before running. Trust is established by HTTPS +
the published `SHA256SUMS` (which the install scripts verify) and the
pinned version. This holds for CI agents as well: they run unattended but
verify the checksum the same way. See the signing table in the old
distribution investigation notes (superseded) -- the short version: no
executable signing applies anywhere.

## What Was Considered And Decided

Investigation notes covering every candidate target (Homebrew, Scoop,
Winget, Chocolatey, APT/PPA, RPM/COPR, Nix, AUR, Snap) are summarized by
their outcomes:

- Homebrew/Scoop/Chocolatey/Winget/APT/RPM/AUR: rejected -- the universal
  tarball + install scripts serve all users with less moving parts.
- Snap: rejected -- strict confinement fights git's subprocess usage.
- Nix: not a CI artifact; a nixpkgs PR could be added later on demand.
- External accounts: none are needed for the chosen distribution path.
  No API keys, no package-manager accounts, no signing keys to protect.

## Distributing To CI Agents

Consumers install git-nest in CI pipelines; the recipes (per CI system,
credentials for private subprojects, caching, agent images) are in
`docs/ci-consumer-guide.md`. For long-lived agents, bake the install into
the agent image at build time with a pinned `VERSION`; for ephemeral
runners, use the one-liner per job.

## Release Process And Main Protection

The intended end-state for the repository (main locked, PR-only merges
gated by CI, publish on merge) is described in
`development/release-process.md`.
