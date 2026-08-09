# Release Process And Main Protection

How releases happen and how `main` is protected: PR-only merges gated by
the full CI suites, automatic Pages deployment on merge, and automatic
release (tag + GitHub Release) when the merged version is newer than the
last release tag.

## CI Trigger Matrix

| Workflow | On PR | On merge to main | Runs |
|----------|-------|-------------------|------|
| `ci-linux.yml` | yes | yes | Full test suite (Linux) |
| `ci-macos.yml` | yes | no | Full test suite (macOS) |
| `ci-windows.yml` | yes | no | Full test suite (Windows) |
| `ci-macos-fast.yml` | no | yes | Fast platform set (macOS) |
| `ci-windows-fast.yml` | no | yes | Fast platform set (Windows) |
| `ci-linux-fast.yml` | no | no | Manual only |
| `pages.yml` | no | yes | Jekyll site build + deploy |
| `release.yml` | no | yes | Version gate -> assemble -> release -> pages |

Every pull request runs the **full** suites on all three platforms
(Linux, macOS, Windows). A merge to main re-runs the full Linux suite
plus the fast macOS/Windows sets, deploys the Pages site, and starts the
release workflow.

## Release On Merge

`release.yml` runs on every push to `main`. Its first job runs the
version gate (`scripts/package/version-check.sh`), which compares
`GIT_NEST_VERSION` against the newest release tag:

- **Version bumped** (`x.y.z` strictly newer than the last `vX.Y.Z`
  tag): the gate sets `is_release=true`, and the pipeline continues:
  assemble (tarball + zip + SHA256SUMS) -> `gh release create` (which
  creates both the `vX.Y.Z` tag and the GitHub Release) -> Pages refresh.
- **Version not bumped** (a docs or fix merge): the gate sets
  `is_release=false`; the remaining jobs are skipped, so non-release
  merges cost only the gate job instead of failing the workflow.

The PR CI already runs the same gate (`check_version_gate` inside
`test_0004`), so a merge to main only ever carries a version bump when
the PR intended one. The PR does not create the tag -- the release
workflow does, after merge, from the merged `main` commit.

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
2. Merge the PR to `main` once the full CI suites pass.
3. The release workflow fires automatically on the merge, creates the
   `vX.Y.Z` tag and the GitHub Release with the version.md entry as
   notes, and refreshes the Pages site.

No manual release steps; no manual tags.
