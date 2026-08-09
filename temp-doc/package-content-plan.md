# Package Content And Build Plan

Personal research notes. NOT committed (temp-doc/ is gitignored).
Goal: build distribution packages that contain git-nest itself, the
installer/uninstaller pair, manuals (converted from docs/), and the AI
skill -- for every target in the distribution investigation.

## Package content (same for every format)

Every package ships the same logical content, assembled by one build step:

1. **git-nest payload**: `bin/` -- git-nest, git_nest.sh, git-nest.bat,
   git-nest.ps1, lib/ (the launchers resolve lib/ relative to themselves,
   so bin/ stays one directory).
2. **Installer + uninstaller**: `bin/install.sh`, `bin/uninstall.sh`,
   `bin/install.bat`, `bin/uninstall.bat` (shipped inside the payload; a
   package manager uses its own install mechanism but users can also
   install/uninstall manually).
3. **Manuals (converted from docs/)**: the markdown docs are the source of
   truth; packages get rendered forms:
   - **man pages** (Linux/macOS): `git-nest.1` (README-derived usage) and
     `git-nest-<topic>.1` for the key docs, rendered with pandoc.
   - **HTML docs** (all platforms): docs/ converted to HTML for `--help`-style
     offline browsing and for the future GitHub Pages site.
   - Packages that only ship files (tar.gz/zip) include the raw `docs/`
     markdown plus the generated man/HTML.
4. **AI skill**: `skills/git-nest/SKILL.md` (+ the `.agents/skills`
   pointer) shipped as `share/git-nest/skill/` so consumers can install it
   into their AI tool of choice.

Common metadata: LICENSE (MIT), version from `GIT_NEST_VERSION`
(single source of truth, enforced by check_version_alignment).

## Which docs become which manuals

| Doc | man page | Notes |
|-----|----------|-------|
| README.md | `git-nest.1` | primary usage manual |
| docs/manifest.md | `git-nest-manifest.5` | .gitnest format reference |
| docs/command-behavior-contract.md | `git-nest-contract.1` | per-command behavior |
| docs/examples.md | `git-nest-examples.1` | walkthroughs |
| docs/howto.md | `git-nest-howto.1` | recipes |
| docs/exit-codes.md | `git-nest-exit-codes.5` | exit code table |
| docs/technical_docs.md | `git-nest-technical.1` | implementation notes |
| docs/maintainer.md | not shipped | maintainer-only |
| docs/ci_and_dockerized_testing.md | not shipped | maintainer/CI-only |
| docs/posix_compatibility_testing.md | not shipped | maintainer/CI-only |
| docs/posix_skill_improvements.md | not shipped | dev notes |
| SECURITY.md | `git-nest-security.5` | security policy |

Maintainer-only docs (maintainer.md, CI/testing docs, posix notes) do NOT
ship in packages -- they are for git-nest developers, not consumers.

## Build architecture

One "assemble" step produces a staging directory, then per-format steps
package it:

```
scripts/package/assemble.sh
  |-- stage/
  |   |-- bin/                 (payload: tool + installers)
  |   |-- share/man/man1|man5  (pandoc-generated man pages)
  |   |-- share/doc/git-nest/  (raw docs/ markdown + generated HTML)
  |   `-- share/git-nest/skill/(skills/git-nest/SKILL.md)
  |-- tar.gz + zip             (universal)
  |-- deb                      (dpkg-deb)
  |-- rpm                      (fedora container, rpmbuild)
  |-- brew formula             (sha256 of tarball)
  |-- scoop manifest           (sha256 of zip)
  |-- winget manifest          (sha256 of zip)
  |-- chocolatey nuspec        (choco pack)
  `-- AUR PKGBUILD             (sha256 of tarball)
```

The assemble script is pure POSIX sh (fits the project style).

### Pandoc: Docker image is canonical, local is optional

Pandoc must NOT be a hard dependency for maintainers. The canonical
converter is the pinned Docker image `pandoc/core:3.10`; the local
`pandoc` binary is only a convenience fallback for quick iteration.

- **CI**: always runs the man/HTML conversion inside
  `docker run --rm pandoc/core:3.10`, so every build uses exactly 3.10.
- **Local**: if `pandoc` is installed, it is used; otherwise Docker is
  used; if neither, the man/HTML step is skipped with a warning (the
  assemble script still produces the tarball with raw docs/). Local
  pandoc on Windows writes CRLF; the build normalizes generated man/HTML
  to LF so local and CI outputs are byte-identical.
- Verified: `pandoc/core:3.10` output is identical to local pandoc 3.10
  modulo line endings.
- Version pin: `PANDOC_IMAGE=pandoc/core:3.10` is a single variable at
  the top of the conversion script; bump it deliberately (it is the
  version the man pages were generated with).
- **Pulling the image locally is a non-issue**: the integration test
  suite already pulls Docker images (Alpine/Debian cross-shell runners),
  so maintainers running the package build locally already have the
  Docker daemon warmed up. No extra burden.

### GitHub Pages from the same pandoc output

The pandoc-generated HTML doubles as the GitHub Pages site content, so
packages and the website come from the same converter and stay in sync:

- `generate-docs.sh` emits HTML pages (one per shipped doc) into
  `stage/share/doc/git-nest/html/`.
- A small `site-index` step generates `index.html` linking the pages, plus
  a copy of the README as the landing page.
- `.github/workflows/pages.yml` (manual, like the other workflows) runs
  the same `assemble.sh` (or just `generate-docs.sh` + index) and deploys
  the HTML with `actions/upload-pages-artifact` + `actions/deploy-pages`.
- Result: the website at `f-steff.github.io/git-nest` and the man/HTML in
  the packages are byte-identical, generated by the same pinned
  `pandoc/core:3.10`.

## Per-format layout

### Platform-specific content (verified against the launchers)

The Windows `.bat`/`.ps1` launchers do NOT forward directly to
`git_nest.sh`; they forward to the adjacent `git-nest` sh entrypoint
(`$SCRIPT=%~dp0git-nest`, `$shellScript = Join-Path $scriptDir "git-nest"`),
which sources `git_nest.sh`. So `git-nest` (the sh entrypoint) is required
on Windows too.

**Design decision**: there is ONE universal package (tar.gz + zip) holding
every file; the per-platform installers copy only the files relevant to
their system.

| Platform | Installer copies | Docs installed |
|----------|-----------------|----------------|
| POSIX (install.sh) | `git-nest`, `git_nest.sh`, `lib/`, install/uninstall.sh | man (man1/man5), md + html, skill |
| Windows (install.bat) | `git-nest`, `git-nest.bat`, `git-nest.ps1`, `git_nest.sh`, `lib/`, install/uninstall.bat | md + html (no man; no `man` on Windows), skill |

Artifacts:
- `git-nest-<v>.tar.gz` (universal, POSIX-readable)
- `git-nest-<v>.zip` (universal, Windows-readable)

| Format | Files installed to | Notes |
|--------|--------------------|-------|
| tar.gz/zip | extracted by user | universal; contains bin/, docs/, man/, skill/ |
| installer (install.sh/bat) | `$prefix/bin`, `$prefix/share/man`, `$prefix/share/doc`, `$prefix/share/git-nest/skill` | installer copies the whole staging tree, not just bin/ |
| .deb | `/usr/bin` (or /usr/lib/git-nest/bin symlinked), `/usr/share/man/man1|man5`, `/usr/share/doc/git-nest`, `/usr/share/git-nest/skill` | dpkg-deb, no build |
| .rpm | same as .deb | rpmbuild in fedora container |
| brew | $(brew --prefix)/bin etc. | formula with sha256 of tarball |
| scoop | scoop apps dir | manifest with sha256 of zip |
| winget | %LOCALAPPDATA% | manifest with InstallerSha256 |
| choco | %ProgramData%\chocolatey | nuspec downloads zip |
| AUR | /usr/bin etc. | PKGBUILD with sha256 of tarball |
| Docker agent image | baked in | docker/agent-image/Dockerfile + docs + man + skill |

## Changes to the installer scripts

Current installers copy only `bin/`. They must be extended to copy the
full staging tree (payload, man, doc, skill) so a manual install gives the
same content as a package:

- install.sh: `cp -R "$from/bin" ...` -> also copy `share/` if present in
  the source (tarball), and create the prefix/share structure.
- install.bat: same on Windows.
- uninstall.sh/bat: remove the extra share/ directories too.

This is the main code change required by the plan.

## CI workflow

One manual `release.yml` (from the feasibility notes):
1. `assemble` job: build staging tree, generate man/HTML, create tar.gz +
   zip + SHA256SUMS, upload artifacts.
2. `packagers` job matrix (or sequential): deb, rpm, brew formula push,
   scoop push, winget PR, choco push, AUR push -- each with its secrets.
3. Optional: build + push the Docker agent image (ghcr.io).

## Verification

- After assembly: `git-nest version` from the staging bin, man pages
  render (`man -l git-nest.1`), skill file present.
- Installer round-trip: install staging tree to temp prefix, run
  `git-nest version`, uninstall, confirm removal (reuses the tests done
  for install.sh/bat/uninstall.sh/bat).
- Per-format: package managers' own lint (`lintian` for deb,
  `rpmlint` for rpm, `brew audit`, `scoop lint`, winget validation).

## Order of work

1. Extend install.sh/uninstall.sh + install.bat/uninstall.bat to handle
   the full staging tree (docs/man/skill).  DONE (install.sh/uninstall.sh
   handle both legacy bin/ tarballs and the full staging tree;
   install.bat/uninstall.bat exist with user/current/system PATH modes).
2. Write scripts/package/assemble.sh (stage + tar.gz/zip + SHA256SUMS).
   DONE -- verified: full staged install -> version -> uninstall cycle.
3. Add man-page generation (pandoc) for the shipping docs. DONE --
   scripts/package/generate-docs.sh (Docker pandoc/core:3.10 canonical,
   local pandoc fallback, graceful skip; emits man1/man5 + HTML + index).
4. Add per-format packagers (deb first, then rpm, then brew/scoop/winget/
   choco/AUR manifests as data files).  NOT STARTED.
5. Wire into a manual release.yml workflow.  NOT STARTED (pages.yml is
   done; release.yml builds on assemble.sh + packagers).
6. Extend the installer smoke workflow to verify a full-staged install.
   NOT STARTED.
7. GitHub Pages: .github/workflows/pages.yml DONE (manual; builds
   site/html via generate-docs.sh, deploys with upload-pages-artifact@v5
   + deploy-pages@v5; requires enabling Pages in repo settings with
   "GitHub Actions" as the source).

## Open questions

- Man page names: `git-nest.1` vs `git-nest.5` for manifest/exit-codes
  (5 = file formats/conventions) -- proposal above; confirm.
- Should the HTML docs use pandoc's standalone template or a project
  stylesheet? (Default template is fine for now.)
- Does winget/choco accept docs/man/skill in a zip installer, or only the
  exe? (Affects whether the zip contains the full staging tree or just
  bin/.)
- Keep the `docs/` raw markdown in the tarball, or only generated man/HTML?
  (Proposal: both -- raw markdown is useful, man/HTML for reading.)
