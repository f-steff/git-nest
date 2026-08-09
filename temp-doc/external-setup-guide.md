# External Setup Guide For Distribution Targets

Personal notes. NOT committed (temp-doc/ is gitignored). Step-by-step
instructions for setting up the external accounts, tokens, and secrets
needed by the release workflow's distribution targets. Work through these
when you are ready to enable each target; until then the corresponding
jobs in `.github/workflows/release.yml` stay disabled (the Chocolatey job
fails cleanly when its secret is absent).

Where secrets go: GitHub repo -> Settings -> Secrets and variables ->
Actions -> New repository secret.

## 0. Prerequisites for all targets

- The repository must be **public** before any external service can see
  releases or badges (Chocolatey, Homebrew taps, Scoop buckets, Winget
  PRs, COPR, PPA, AUR all fetch from the public GitHub releases).
- A `GITHUB_TOKEN` (the default token) is sufficient for GitHub Releases
  and Pages. Everything below that needs to push to ANOTHER repo or
  account needs its own credential.

## 1. Chocolatey (windows) -- `CHOCO_API_KEY`

1. Create an account at https://community.chocolatey.org.
2. Go to https://community.chocolatey.org/account and note your API key.
3. Request maintainer rights for the `git-nest` package id (the first
   `choco push` may create the package; if it says the id is taken by
   someone else, open a support request to transfer it).
4. Add the API key as a repo secret named `CHOCO_API_KEY`.
5. The release workflow already packs `packaging/chocolatey/git-nest.nuspec`
   and pushes with `choco push ... --key $CHOCO_API_KEY`.

## 2. Homebrew (macOS + Linux) -- personal tap

Recommended: a personal tap repo (no review, fully automated).

1. Create a repo `f-steff/homebrew-tap` (must be named `homebrew-tap`).
2. The release workflow will need to push the updated formula there.
   Create a fine-grained PAT with `contents: write` on
   `f-steff/homebrew-tap` only, or use the default `GITHUB_TOKEN` if the
   tap lives in the same account (fine-grained token with access to that
   repo).
3. Add it as a secret `HOMEBREW_TAP_TOKEN`.
4. Enable the brew job in `release.yml` and fill
   `packaging/brew/git-nest.rb` (URL + sha256 are injected at build time).

Alternative (homebrew-core): submit a PR with the formula; the
`HOMEBREW_GITHUB_API_TOKEN` (a PAT with access to homebrew-core) is used
by `brew bump-formula-pr` for automated updates.

## 3. Scoop (windows) -- personal bucket

1. Create a repo `f-steff/scoop-git-nest` (or `ScoopInstaller/...` style
   bucket name).
2. The release workflow pushes `packaging/scoop/git-nest.json` to the
   bucket. Needs a fine-grained PAT with `contents: write` on that repo
   (secret `SCOOP_BUCKET_TOKEN`) or the default token if same-account.
3. Users install with:
   `scoop bucket add git-nest https://github.com/f-steff/scoop-git-nest`
   `scoop install git-nest`

## 4. Winget (windows) -- microsoft/winget-pkgs

1. No account registration, but updates are PR-based.
2. The release workflow uses `wingetcreate update` and submits a PR to
   `microsoft/winget-pkgs`; needs a PAT with `public_repo` scope, stored
   as `WINGET_TOKEN`.
3. Open question (see the package-content plan): whether a zip containing
   only `git-nest.bat`/`git-nest.ps1` (no .exe) is accepted. Research
   `installerType: zip` before enabling.

## 5. APT / Debian -- Launchpad PPA (or self-hosted repo)

PPA route:
1. Create a Launchpad account: https://launchpad.net/+login.
2. Generate an OpenPGP key (`gpg --full-generate-key`), upload the public
   key to Launchpad (https://launchpad.net/~<you>/+editpgpkeys).
3. Add your SSH public key to Launchpad (https://launchpad.net/~<you>/
   +editsshkeys).
4. Create the PPA: https://launchpad.net/~<you>/+activateppas ->
   create `git-nest`.
5. Secrets: `PPA_SSH_KEY` (the private key) and `PPA_GPG_KEY` (the OpenPGP
   private key) for signing the .changes files.
6. Enable the deb job in `release.yml` using the `packaging/debian/`
   control file.

Self-hosted alternative: host `dists/` + `pool/` on GitHub Pages or
Releases with a signed `Release` file; needs only the OpenPGP signing key.

## 6. RPM / Fedora -- COPR (or self-hosted repo)

COPR route:
1. Create a Fedora Account System account: https://accounts.fedoraproject.org
2. Enable COPR: https://copr.fedorainfracloud.org (follow the onboarding).
3. Generate an API token: https://copr.fedorainfracloud.org/api/ (store
   the full token; the login and token parts go in the secret).
4. Add your SSH public key to COPR settings.
5. Secrets: `COPR_API_TOKEN` (and the SSH key if used).
6. Enable the rpm job in `release.yml` using `packaging/rpm/git-nest.spec`.

Self-hosted alternative: yum repo on GitHub Pages/Releases + a signing
GPG key (`RPM_GPG_KEY` secret).

## 7. AUR (arch) -- aur.archlinux.org

1. Create an AUR account: https://aur.archlinux.org/register.
2. Add your SSH public key: https://aur.archlinux.org/account -> My
   Account -> SSH Public Key.
3. Secret: `AUR_SSH_KEY` (the private key).
4. Enable the aur job in `release.yml` pushing
   `packaging/aur/PKGBUILD` (URL + sha256 injected).

## 8. Snap (deferred -- not recommended yet)

1. snapcraft.io account + `SNAPCRAFT_STORE_CREDENTIALS`.
2. Snaps are signed by the store; strict confinement may block git-nest's
   `git` subprocess execution patterns (would need classic confinement
   review). Deferred; not part of the release workflow.

## Checklist summary

| Target | Secret(s) | Account needed? | Status |
|--------|-----------|-----------------|--------|
| GitHub Releases | (default token) | no | enabled |
| Pages | (default token) | no | enabled |
| Chocolatey | `CHOCO_API_KEY` | choco.org account + package-id rights | enabled (fails without secret) |
| Homebrew | `HOMEBREW_TAP_TOKEN` | tap repo | stub |
| Scoop | `SCOOP_BUCKET_TOKEN` | bucket repo | stub |
| Winget | `WINGET_TOKEN` | none (PR-based) | stub + open question |
| APT/PPA | `PPA_SSH_KEY`, `PPA_GPG_KEY` | Launchpad account | stub |
| RPM/COPR | `COPR_API_TOKEN` | Fedora account | stub |
| AUR | `AUR_SSH_KEY` | AUR account + SSH key | stub |
| Snap | `SNAPCRAFT_STORE_CREDENTIALS` | snapcraft account | deferred |
