# Release Process And Main Protection

How releases happen today, and the intended end-state for the repository
once the project is settled: a protected `main`, PR-only merges gated by
CI, and publication on merge.

## Current State (Transitional)

- All CI workflows are manual (`workflow_dispatch` only): the six test
  workflows (fast + full x Linux/macOS/Windows), the Pages workflow, and
  the Release workflow.
- `main` is unprotected: pushes and direct commits are possible.
- Releases are created manually by running the Release workflow and
  reviewing its output.

## Future End-State

The goal is a publish-on-merge model:

1. **`main` is locked.** Branch protection rules on `main`:
   - Require a pull request before merging; no direct pushes.
   - Require the fast CI set to pass on the PR before merge: the three
     `ci-*-fast.yml` workflows (Linux, macOS, Windows). These cover the
     unit suite, static analysis, and the platform-sensitive tests, so
     every merge is verified on all three OSes without waiting ~45
     minutes for the full Windows suite.
   - Require linear history (or squash merges) so `main` stays clean and
     bisectable.
2. **Merges gate the full suite.** The full CI workflows
   (`ci-*-full.yml` / the full runs) run on every merge to `main` (push
   trigger), giving full verification across all three platforms
   including the long Windows run. A red full suite on `main` is
   immediately actionable.
3. **Release on merge.** When a release is wanted:
   - Bump `GIT_NEST_VERSION` in `bin/git_nest.sh` + the version.md
     changelog entry in the PR (the existing `check_version_alignment`
     and `version-check.sh` gates keep them in lockstep).
   - Merging to `main` triggers the Release workflow on push (or it stays
     manual and is run after the merge -- whichever is preferred once
     automation lands).
   - The Release pipeline runs: full test suite -> version gate ->
     assemble -> GitHub Release -> Pages refresh.

## What This Requires

- Branch protection settings on `main` (a one-time repo Settings change).
- CI workflows that trigger on `pull_request` (fast set) and `push` to
  `main` (full set + optionally release). Today everything is manual;
  flipping the triggers is the main automation step.
- Discipline: every behavior change lands with tests, and the version
  bump lives in the same PR as the change it ships.

## Sequence To Get There

1. Keep everything manual while the project stabilizes (current state).
2. Enable branch protection on `main` with required PR review and
   required fast-CI checks.
3. Wire the fast workflows to `pull_request` and the full workflows to
   `push` on `main`.
4. Decide release trigger: automatic on merge (tag push) or manual
   release workflow run after merge.
5. Revisit and document the exact trigger choices here as they land.
