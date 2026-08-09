# Distribution Artifact CI Feasibility

Personal research notes. NOT committed (temp-doc/ is gitignored).
Answers: "how many of the distribution artifacts can we currently build as
manually-triggered CI workflows?"

## Current state

The repo has **6 workflows, all testing** (fast + full x Linux/macOS/Windows,
manual `workflow_dispatch`). **Zero release/packaging workflows exist yet.**

## Feasibility per artifact (as a manual GitHub Actions workflow)

Legend: NOW = buildable today with zero new accounts; ACCT = needs a
one-time registration/secret; LATER = needs an open question resolved or
too much friction.

| # | Artifact | Buildable in CI now? | Runner/tools | Extra requirements |
|---|----------|---------------------|--------------|--------------------|
| 1 | Universal tarball (`bin/` + LICENSE) | **NOW** | ubuntu-latest, `tar` | none |
| 2 | Universal zip | **NOW** | ubuntu-latest, `zip` (or `python3 -m zipfile`) | none |
| 3 | `SHA256SUMS` file | **NOW** | `sha256sum` | none |
| 4 | Installer script (`curl \| sh`) | **NOW** | committed in repo, included in tarball | none |
| 5 | Homebrew formula + tap push | **NOW** | push to personal tap repo | `GITHUB_TOKEN` on tap repo |
| 6 | Scoop manifest + bucket push | **NOW** | push to bucket repo | `GITHUB_TOKEN` on bucket repo |
| 7 | AUR PKGBUILD push | ACCT | `ssh` to aur.archlinux.org | AUR account + `AUR_SSH_KEY` |
| 8 | Winget manifest | ACCT | PR to microsoft/winget-pkgs | `WINGET_TOKEN`; open question: zip-without-exe accepted? |
| 9 | Chocolatey nupkg + push | ACCT | Windows runner with choco, or `choco pack` anywhere | choco.org account + `CHOCO_API_KEY` |
| 10 | APT `.deb` + self-hosted repo | **NOW** | ubuntu-latest `dpkg-deb`; repo files + OpenPGP-signed `Release` | OpenPGP signing key (secret) |
| 11 | APT via Launchpad PPA | ACCT | `dput` over SSH | Launchpad account + SSH key + OpenPGP |
| 12 | RPM `.rpm` + self-hosted repo | **NOW** | `fedora:latest` container, `rpmbuild` + `rpmsign` | OpenPGP signing key (secret) |
| 13 | RPM via COPR | ACCT | `copr-cli` | Fedora account + `COPR_API_TOKEN` |
| 14 | Nix | n/a | nixpkgs PR (not a CI artifact) | none (bot-managed) |
| 15 | Snap | ACCT | snapcraft remote build | snapcraft.io account + `SNAPCRAFT_STORE_CREDENTIALS`; confinement question |

## Summary

- **9 of 15 artifacts are buildable today** as manual workflows with zero
  new accounts (tarball, zip, SHA256SUMS, installer, Homebrew tap, Scoop
  bucket, self-hosted APT, self-hosted RPM, and -- with a one-time secret
  -- AUR).
- **5 need registration/secrets** (Winget, Chocolatey, PPA, COPR, Snap).
- **1 is not a CI artifact** (Nix, PR-based).

## Recommended first workflow

A single manual `release.yml` that builds artifacts 1-4 (tarball, zip,
SHA256SUMS, installer) and uploads them to a GitHub Release, then chains:
Homebrew tap push + Scoop bucket push + AUR push. This covers artifacts
1-7 with only the AUR SSH key as a new secret.

## Other CI systems

- **Azure Pipelines / Gitea / Jenkins**: the *testing* workflows are the
  portable part. Packaging is a release concern; the artifact-building
  steps (tar/zip/dpkg/rpmbuild) are shell commands that port to any of
  them, but the "push to GitHub Release" step is GitHub-specific. For
  self-hosted Gitea/Jenkins, the same build steps can push to Gitea
  Releases (Gitea has them) or a local artifact server instead.
