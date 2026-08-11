# Release Process And Main Protection

How releases happen and how `main` is protected: PR-only merges gated by
the full CI suites. Releases are **manual** -- merging to `main` never
creates a tag or a GitHub Release by itself; a maintainer explicitly
dispatches the Release workflow when a release is wanted.

## CI Trigger Matrix

| Workflow | On PR | On merge to main | Runs |
|----------|-------|-------------------|------|
| `ci-linux.yml` | yes | no | Full test suite (Linux) |
| `ci-macos.yml` | yes | no | Full test suite (macOS) |
| `ci-windows.yml` | yes | no | Full test suite (Windows) |
| `ci-macos-fast.yml` | no | yes | Fast platform set (macOS) |
| `ci-windows-fast.yml` | no | yes | Fast platform set (Windows) |
| `ci-linux-fast.yml` | no | no | Manual only |
| `pages.yml` | no | no | Manual + called by release |
| `release.yml` | no | no | Manual only |

The three full CI workflows also run on push to release tags (`v*`) so
the GitHub Pages site can display version-pinned CI badges
(`?branch=v{{ site.version }}`) that reflect the release version's test
status rather than the live development-branch state. The Release
workflow dispatches these tag runs automatically via its `tag-ci` job.

Every pull request runs the **full** suites on all three platforms
(Linux, macOS, Windows). A merge to `main` runs only the fast macOS and
Windows sets: the full PR CI already gated the merge, so the merge itself
does not re-run the full suite.

## Manual Releases

`release.yml` is a `workflow_dispatch` action -- it runs only when a
maintainer dispatches it (Actions -> Release -> Run workflow, with an
optional notes override). Its first job runs the version gate
(`scripts/package/version-check.sh`), which compares `GIT_NEST_VERSION`
against the newest release tag:

- **Version bumped** (`x.y.z` strictly newer than the last `vX.Y.Z`
  tag): the pipeline continues: assemble (tarball + zip + SHA256SUMS) ->
  `gh release create` (which creates both the `vX.Y.Z` tag and the GitHub
  Release) -> tag CI dispatch -> Pages refresh.
- **Version not bumped**: the workflow fails with a clear message. A
  manual dispatch is an explicit release request, so silently skipping
  would be confusing; bump the version first, then dispatch again.

The PR CI already runs the same gate (`check_version_gate` inside
`test_0004`), so main only ever carries a version bump when a PR
intended one. The tag is created by the Release workflow from the merged
`main` commit -- never by a merge itself.

## Main Protection

`main` is protected in the repository settings (Settings -> Rules ->
Rulesets -> branch ruleset targeting `main`):

- Require a pull request before merging; direct pushes are blocked.
- Require status checks: `CI (Linux)`, `CI (macOS)`, `CI (Windows)` --
  the full suites must pass on the PR before it can merge.
- Require conversation resolution.
- Force pushes are blocked. Undoing a bad merge therefore uses a
  **revert PR** (a normal PR that reverses the previous merge), never a
  history rewrite.

Merges use squash-merge; the commit message (header + body) is taken
from the PR description so `main` history stays clean and readable.

## Making A Release

1. In the PR: bump `GIT_NEST_VERSION` in `bin/git-nest-main.sh` and add
   the `version.md` changelog entry (the version alignment check in
   `test_0004` enforces they match; the version gate enforces the bump).
   Merge the PR to `main` once the full CI suites pass. Merging does not
   release anything by itself.
2. When the release is wanted, dispatch the Release workflow manually
   (Actions -> Release -> Run workflow). Optionally provide release notes
   in the `notes` input; without them, the newest version.md entry is
   used.
3. The workflow verifies the version bump, creates the `vX.Y.Z` tag and
   the GitHub Release with the version.md entry as notes, dispatches the
   tag CI (so the Pages badges get a status), and refreshes the Pages
   site.

No release happens automatically on merge; no manual tags.
