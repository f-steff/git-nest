# git-nest Distribution Investigation

Personal research notes. NOT committed (temp-doc/ is gitignored). Goal: use
GitHub Actions CI to package and publish git-nest to various package
managers, from a single release workflow.

## What git-nest ships

Everything is in `bin/` (~385 KB, plain text shell):

```
bin/git-nest            POSIX entrypoint (sh)
bin/git_nest.sh         shared implementation (sources bin/lib/)
bin/lib/*.sh            library modules (~9,900 lines total)
bin/lib/*.awk           parsers
bin/git-nest.bat        Windows cmd.exe launcher (polyglot)
bin/git-nest.ps1        PowerShell 7+ launcher (cross-platform)
bin/.shellcheckrc       shellcheck config (not needed by users)
```

Key distribution insight: **there is no build step**. A package just needs to
place `bin/` on PATH (and keep the relative layout, since `git_nest.sh`
sources `bin/lib/` relative to itself). Completions are generated on demand
(`git-nest completion <shell>`), so packages do not need to ship them.

A release artifact is simply a tarball/zip of `bin/` (optionally plus
LICENSE, README, docs). Since the tool is pure shell, the SAME artifact
works on every platform -- no per-OS binaries.

## Candidate targets (from todo.md)

| Target | Platform | Difficulty | CI integration |
|--------|----------|-----------|----------------|
| GitHub Releases + tarball | all | trivial | native |
| Shell installer script | all (POSIX) | easy | native |
| Homebrew | macOS + Linux | easy | GitHub repo tap |
| Scoop | Windows | easy | GitHub repo bucket |
| Winget | Windows | medium | GitHub repo manifest |
| Chocolatey | Windows | medium | choco.org account |
| APT (.deb) | Debian/Ubuntu | medium | PPA or own repo |
| RPM (.rpm) | Fedora/RHEL | medium | COPR |
| Nix | all | medium | nixpkgs PR |
| AUR | Arch | easy | AUR repo |
| Snap | Linux | hard (snapcraft) | snapcraft.io |

## Strategy recommendation

Two-layer approach:

1. **Foundation (do first, covers everyone):** GitHub Releases with a
   universal `git-nest-<version>.tar.gz`/`.zip` of `bin/` + a one-line
   shell installer script. This is pure GitHub, no external accounts, and
   immediately lets users install anywhere with:
   ```sh
   curl -fsSL https://github.com/f-steff/git-nest/releases/latest/download/install.sh | sh
   ```

2. **Curated package managers (pick based on audience):** Homebrew (core tap
   or a personal tap), Scoop, Winget. These three are the mainstream macOS
   + Windows channels. APT/RPM/Nix/AUR/Chocolatey/Snap are possible later.

---

## Foundation: GitHub Releases

### CI workflow (concept)

```yaml
name: Release
on:
  workflow_dispatch:            # manual for now; later: tag push
  push:
    tags: ['v*']
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Create release tarballs
        run: |
          tar -czf git-nest-${GITHUB_REF_NAME}.tar.gz -C bin .
          zip -r git-nest-${GITHUB_REF_NAME}.zip bin
      - uses: softprops/action-gh-release@v2   # or gh CLI
        with:
          files: |
            git-nest-*.tar.gz
            git-nest-*.zip
```

### How to enable (one time)

1. Repo Settings -> General -> scroll down -> set default branch (already main).
2. Repo Settings -> Actions -> General -> "Workflow permissions":
   - Set "Read and write permissions" -- needed so the release workflow can
     create releases/upload assets. (Or use a PAT secret, see below.)
3. Nothing else is needed for GitHub Releases themselves; they are native.

### Installer script

A `bin/install.sh`-style script committed to the repo (not required, but
makes the "curl | sh" one-liner work). Considerations:
- Detect OS (`uname -s`), choose ~/.local/bin (Linux/macOS) or document
  Windows manual install.
- Download the release tarball, extract `bin/` into
  `~/.local/share/git-nest/` or `$HOME/.git-nest/`, symlink/copy the three
  launcher names into `~/.local/bin/`.
- Verify the tarball checksum (publish a SHA256SUMS in the release).
- Security note: `curl | sh` needs the script to be signed/checksummed or
  served over HTTPS from the pinned repo (HTTPS is the baseline).

### Code signing (shell tool)

A shell-script tool has **no executable to sign**: the payload is plain
text, and no platform requires a signature on `.sh`/`.bat`/`.ps1` files
before they run (PowerShell execution policy is a local policy, not a
signature requirement; unsigned `.ps1` runs with `-ExecutionPolicy Bypass`).
Trust is established by:

- HTTPS + a published `SHA256SUMS` file (verify the tarball hash), and
  ideally a PGP signature over `SHA256SUMS` using a dedicated release
  signing key so users can verify authenticity without trusting HTTPS
  alone.
- The package manager's own integrity check (brew/Scoop/Winget/AUR hash the
  artifact; APT/RPM sign the repository).

So for the shell distribution, **checksums + HTTPS are sufficient**;
executable code signing (Authenticode, Apple notarization) is not
applicable.

---

## Homebrew (macOS + Linux)

### Options

A) **Homebrew-core** -- the official tap. High bar: formula review, tests,
   a stable tarball URL, and usually a "bottle" (prebuilt) or a from-source
   build. For a shell script, a `formula` with `url` + `sha256` of the
   release tarball and no build step is straightforward. Requires a PR to
   https://github.com/Homebrew/homebrew-core. New formulas need maintainer
   review; updates happen via automated PRs once `brew bump-formula-pr` is
   set up (needs a GitHub token secret).

B) **Personal tap** -- you own
   `https://github.com/f-steff/homebrew-tap` with a formula that points at
   your release tarball. No review. Users run:
   ```sh
   brew tap f-steff/tap
   brew install git-nest
   ```

### Registration / secrets

- Homebrew-core: no account registration, but the formula's `sha256` must
  be updated on every release. Automation: `brew bump-formula-pr` run in CI
  with `HOMEBREW_GITHUB_API_TOKEN` (a fine-grained PAT with repo access to
  homebrew-core, or the default `GITHUB_TOKEN` only works for your own repo
  -- homebrew-core needs a PAT).
- Personal tap: push the updated formula to your tap repo from CI using
  `GITHUB_TOKEN` (fine-grained, contents: write on the tap repo) or a PAT.

### Code signing (shell tool)

Homebrew does **not require code signing** for a shell-script formula. The
trust anchor is the formula's `sha256` of the release tarball (Homebrew
verifies it on install) plus HTTPS. No Authenticode/notarization applies
to scripts. A personal tap formula is reviewed by no one, so the sha256
must come from the release workflow (never hand-typed).

---

## Scoop (Windows)

Scoop buckets are git repos with a `bucket/manifest.json` (called an
"app manifest"). Personal buckets are trivial.

- Bucket repo: `https://github.com/f-steff/scoop-git-nest`
  (or add a manifest to the main `ScoopInstaller/Main` bucket via PR).
- Manifest points at the release zip (`url` + `sha256` of the .zip),
  `bin: ["git-nest.bat", ...]` or similar.
- Users: `scoop bucket add git-nest https://github.com/f-steff/scoop-git-nest`
  then `scoop install git-nest`.

### Registration / secrets

- Personal bucket: none. CI pushes the updated manifest with `GITHUB_TOKEN`
  (fine-grained, contents: write on the bucket repo).
- Main bucket: PR-based, needs a maintainer review; automated updates via
  ScoopInstaller's own bot usually handle it once the manifest is accepted.

### Code signing (shell tool)

Scoop verifies the `sha256` in the manifest against the downloaded zip;
that plus HTTPS is the whole trust model. No code signing is needed or
supported for script payloads. (Scoop does not run PowerShell with a
restricted policy for installs; the manifest hash is the protection.)

---

## Winget (Windows)

Winget uses a central community repo
(`microsoft/winget-pkgs`) with per-package manifests
(`manifests/f/f-steff/git-nest/<version>/...yaml`). Users: `winget install git-nest`.

### Registration / secrets

1. Create the manifest files in `microsoft/winget-pkgs` via PR (repo has
   its own validation).
2. The installer must be an .exe/.msi/.msix **or** a portable/zip installer
   with a `installerType: zip` (works for our bin/ zip if it has an .exe
   entry point -- git-nest.bat is NOT an exe, so zip mode may need the
   .ps1 launcher or an explicit "portable" definition; needs research).
3. Updates: `wingetcreate update` in CI, pushed via PR to winget-pkgs,
   needs `WINGET_TOKEN` (a PAT with public-repo write) or manual PRs.

This is one of the more complex targets because of the installer-type
constraint and the PR-based update flow.

### Code signing (shell tool)

Winget validates the manifest's `InstallerSha256` against the downloaded
artifact. For a zip of scripts, that hash is the trust anchor; no
executable signature applies (there is no .exe/.msi to sign). Winget
policy prefers signed installers for exe/msi, but a `zip` installer type
with an accurate sha256 is acceptable for script payloads. The bigger
unknown stays: whether a zip with only `.bat`/`.ps1` entry points is
accepted (see Open questions).

---

## Chocolatey (Windows)

Chocolatey packages are nupkg files hosted at community.chocolatey.org.
Users: `choco install git-nest`.

### Registration / secrets

1. Create an account at https://community.chocolatey.org and request
   "package maintainer" rights for the `git-nest` package id (verification
   process).
2. The package is a `git-nest.nuspec` + `tools/chocolateyinstall.ps1`
   (downloads the release zip, installs bin/).
3. CI publishes with `choco push` using an API key:
   - Store as a repo secret `CHOCO_API_KEY` (from your community.chocolatey.org
     profile -> API Key).
4. Updates require `choco pack` + `choco push` with the new version; the
   package id must stay stable.

### Code signing (shell tool)

Chocolatey does not require Authenticode signing of the nupkg or its
scripts; the trust model is the package's embedded `checksum` of the
downloaded artifact plus the community moderation process. The install
script (`chocolateyinstall.ps1`) downloads the release zip and verifies
the checksum before extracting. No executable signature applies to the
shell payload.

---

## APT (.deb) for Debian/Ubuntu

### Primer: what APT and .deb are

APT (Advanced Package Tool) is the package manager on Debian, Ubuntu, and
derivatives. Packages are `.deb` archives: a `control` file (name, version,
dependencies), the payload files (for git-nest: `bin/` installed to
`/usr/bin` or `/usr/lib/git-nest`), and optional maintainer scripts
(postinst, etc. -- not needed for git-nest). Users install via
`apt-get install` / `apt install`.

For a shell tool like git-nest a `.deb` is a thin wrapper: the package just
extracts `bin/` and creates symlinks/renames for the three launcher names.
No compilation. The real work is in the **repository** around the `.deb`:
APT pulls packages from repos that expose `dists/<codename>/` with a
`Release` file (listing checksums) and a `Packages.gz` index. Building a
`.deb` is easy (`dpkg-deb` or `debuild`); hosting the repo is the hard
part (see options below).

### Options

A) **Launchpad PPA** -- https://launchpad.net: create a PPA
   (`ppa:f-steff/git-nest`), upload .deb source. Users:
   `sudo add-apt-repository ppa:f-steff/git-nest`.
   - Registration: Launchpad account, SSH key upload, PPA creation. CI
     uploads via `dput` with the SSH key as a secret. This is the classic
     path but the most finicky (OpenPGP signing, source package format).

B) **Self-hosted APT repo** -- a GitHub Pages site or GitHub Releases
   holding `dists/` + `pool/` with a Release file signed by an OpenPGP key.
   Users add your repo URL + key. More control, more work to set up.

### Registration / secrets

- PPA: Launchpad account + OpenPGP key (create with `gpg --gen-key`, upload
  to Launchpad) + SSH key. Secrets: the OpenPGP private key (for signing
  .changes files) and the SSH private key (for dput).
- Self-hosted: an OpenPGP signing key (secret), GitHub Pages enabled or
  Releases used as the file host.

### Code signing (shell tool)

APT's trust model is **repository signing, not payload signing**: the
`Release` file (listing checksums of `Packages`/`Sources`) is signed with
an OpenPGP key, and users add that key (`add-apt-repository` or
`apt-key`/sources.list `signed-by=`). The `.deb` contents themselves are
not individually signed; integrity comes from the Release checksums. For a
shell payload this is sufficient -- no per-file signing needed. The OpenPGP
private key is the one secret that must be protected (keep it out of CI
where possible, or use a dedicated CI-signing subkey).

---

## RPM for Fedora/RHEL

### Primer: what RPM and .rpm are

RPM (RPM Package Manager) is the package manager on Fedora, RHEL, and
derivatives (openSUSE uses it too via `.rpm`). Packages are `.rpm`
archives: a header with metadata (name, version, dependencies) and the
payload files (for git-nest: `bin/` installed to `/usr/bin` or
`/usr/lib/git-nest`). The user-facing frontends are `dnf` (Fedora/RHEL)
and `zypper` (openSUSE). Users install with `dnf install`.

Like APT, an `.rpm` for git-nest is a thin wrapper -- the spec file
(`.spec`) just declares the files and install location; there is nothing
to compile. The surrounding infrastructure is the real work: RPM repos
(`repodata/`) contain a `repomd.xml` metadata file with checksums, and the
repo must be signed so `dnf` can verify packages.

### Options

A) **COPR** (https://copr.fedorainfracloud.org) -- the Fedora equivalent of
   PPAs. Create a project, submit SRPMs. Users:
   `dnf copr enable f-steff/git-nest`.
   - Registration: Fedora Account System account, enable COPR, upload SSH
     key. CI pushes SRPMs via `copr-cli` using the API token/secret.

B) Self-hosted RPM repo (yum repo on GitHub Pages/Releases) -- like the APT
   variant, needs a signing key.

### Registration / secrets

- COPR: Fedora account + `copr` API token (from COPR settings) + SSH key.
  Secrets: `COPR_API_TOKEN`, SSH key.

### Code signing (shell tool)

RPM uses **package signing**: the `.rpm` is signed with a GPG key
(`rpmsign --addsign`), and the repo's `repomd.xml` metadata carries the
same signature (`repomd.xml.asc`). `dnf` verifies the repo key when the
user imports it. The payload (scripts) needs no separate signing; the RPM
signature covers the whole archive. COPR signs packages with Fedora's own
keys (users already trust the Fedora keyring); a self-hosted repo needs
its own GPG key published to users.

---

## Nix

Nixpkgs is a single central repo; adding `git-nest` is a PR to nixpkgs
(`pkgs/by-name/gi/git-nest/package.nix`). No per-repo registration, but:
- The derivation wraps `bin/` (a `stdenv` no-build derivation that unpacks
  the tarball).
- Updates: nixpkgs bots (r-ryantm) handle version bumps once merged.
- Users: `nix profile install nixpkgs#git-nest`.

No secrets; PR-based. This is a "nice to have" -- the review bar is code
quality, not accounts.

### Code signing (shell tool)

Nix verifies the `sha256` declared in the derivation against the fetched
source; that hash is the trust anchor (plus nixpkgs review). No code
signing exists in the nix model for sources or built outputs -- content
addressing + hashes replace it. Nothing to set up for the shell tarball.

---

## AUR (Arch)

AUR is a single git repo (aur.archlinux.org); packages are PKGBUILDs.

- Create an AUR account, register an SSH key (AUR uses SSH for pushes).
- `git-nest` PKGBUILD downloads the release tarball, installs `bin/`.
- Users: `yay -S git-nest` or manual `makepkg`.
- CI: push updated PKGBUILD via SSH (secret: AUR SSH private key). Version
  bumps are just a new `pkgver=`.

### Registration / secrets

- AUR account + SSH public key registered at aur.archlinux.org.
- Secret: `AUR_SSH_KEY`.

### Code signing (shell tool)

AUR PKGBUILDs declare `sha256sums` for each source; `makepkg` verifies
them. That hash + HTTPS is the trust model; no code signing applies to
scripts. (AUR is "user submitted, not verified" -- the trust boundary is
the maintainer identity + the hashes, and users are warned by the AUR
warning banner.)

---

## Snap (least recommended)

Snapcraft requires:
- A snapcraft.io account + `snapcraft login` credentials (or a stored
  snapcraft token).
- The snap must be built with `snapcraft` (needs a snap build environment
  in CI, or use the remote build service).
- Strict confinement means the shell tool needs a `snap.yaml` with plugs
  (network, home) and possibly manual approval.
- Secret: `SNAPCRAFT_STORE_CREDENTIALS`.

Given git-nest is a shell tool that shells out to `git`, snap confinement
may cause friction. Defer.

### Code signing (shell tool)

Snaps are **signed by the snapcraft store** (Canonical) at upload time;
users trust the store, not the publisher's key. No publisher-side code
signing exists. However, a shell-in-a-snap needs its interpreter +
`git` available inside the snap's confined environment (bundle `git` as a
snap part or use a `git` content plug) -- this is the real barrier, not
signing. Strict confinement may block the tool's `git` subprocess
execution patterns; would need a `classic` confinement request (manual
review) if it cannot run confined.

---

## Recommended order

1. GitHub Releases + universal tarball + installer script (foundation,
   zero external accounts).
2. Homebrew personal tap (macOS/Linux mainstream).
3. Scoop bucket (Windows, trivial).
4. Winget (Windows mainstream; research the installer-type constraint).
5. AUR (Arch, cheap if you have an account).
6. APT PPA / COPR (Linux distro users; more setup).
7. Chocolatey / Snap / Nix -- later, based on demand.

## Cross-cutting CI notes

- Version source of truth: `GIT_NEST_VERSION` in `bin/git_nest.sh` must
  match version.md (already enforced by check_version_alignment). The
  release workflow should read it from there (`grep '^GIT_NEST_VERSION='`)
  so tags and packages never drift.
- Trigger: recommend `on: push: tags: ['v*']` eventually; keep
  `workflow_dispatch` + a manual version input for now.
- Secrets needed (summary):
  - `GH_TOKEN` or fine-grained `GITHUB_TOKEN` (permissions: contents write)
    for Releases + pushing to personal taps/buckets.
  - `CHOCO_API_KEY` (Chocolatey).
  - `COPR_API_TOKEN` + SSH key (COPR).
  - Launchpad SSH key + OpenPGP key (PPA).
  - `AUR_SSH_KEY` (AUR).
  - `WINGET_TOKEN` (winget-pkgs PRs).
  - `SNAPCRAFT_STORE_CREDENTIALS` (Snap, if ever).
- All secrets go in Repo Settings -> Secrets and variables -> Actions.

## Code signing summary (shell tool)

| Target | Signing needed? | Trust mechanism |
|--------|-----------------|-----------------|
| GitHub Releases | No (PGP on SHA256SUMS optional) | HTTPS + SHA256SUMS |
| Installer script | No | HTTPS + checksum |
| Homebrew | No | formula sha256 |
| Scoop | No | manifest sha256 |
| Winget | No (zip) / Yes (exe) | InstallerSha256 / Authenticode |
| Chocolatey | No | package checksum + moderation |
| APT | Repo signature (OpenPGP Release) | signed Release file |
| RPM | Package signature (GPG) | rpmsign + repo key |
| Nix | No | derivation hash |
| AUR | No | PKGBUILD sha256sums |
| Snap | Store signs | snapcraft store trust |

Bottom line: **a shell tool needs no executable code signing anywhere.**
Where signing exists (APT/RPM) it is repository/package-level with OpenPGP
keys, not per-file Authenticode/notarization.

## Open questions

- Winget: can a `.zip` containing `git-nest.bat`/`git-nest.ps1` (no .exe)
  be an accepted installer? Research `installerType: zip` + `bin` field.
- Homebrew-core vs personal tap: personal tap is frictionless; core is
  higher prestige but needs maintainership commitment.
- Should the release tarball include docs/ and LICENSE? (Yes for packages
  that need them; LICENSE is MIT and should be in the tarball.)
- Whether to publish a `man` page (not currently generated).

## Related: consuming git-nest from CI runners

A separate concern from publishing packages: how CI systems (GitHub
Actions, Azure Pipelines, GitLab, Gitea, Jenkins) install git-nest and use
it in pipelines. See `ci-consumer-integration.md` in this folder.
