# git-nest Implementation Summary

This file is the behavior contract for the current shell implementation.

## Current Scope

`git-nest` manages a reproducible multi-repository workspace. The outer repository owns `.gitnest`; every subproject remains an ordinary Git repository with its own commits, branches, remotes, and push workflow.

The tool records and restores source state. It does not replace `git switch`, `git commit`, `git push`, code review, or release processes.

## Manifest Contract

The manifest schema version is `1`.

Required project section:

```ini
[project]
version=1
```

Subproject sections use quoted paths:

```ini
[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=<sha>
```

Allowed subproject keys are:

- `repo=<url>`: required.
- `clone=full|partial`: optional missing-checkout clone preference.
- `target_branch=<name>`: branch used by `outdated`, `update --target-head`, and normal tracking.
- `revision=<sha>`: exact reproducible commit.
- `tag=<name>`: optional tag name; requires `revision`.

Obsolete pending workflow keys are rejected: `pending_branch`, `base_revision`, `pushed_commit`, and `finalized_from_branch`.

Manifest rewrites preserve unknown extension keys except for keys owned by the current command. Rewrites are deterministic and protected by `.gitnest.lock`.

Manifest lock acquisition waits up to `GIT_NEST_LOCK_TIMEOUT_SECONDS`, defaulting to 10 seconds, before reporting the lock owner metadata and recovery command.

## Command Guarantees

- `init [--rc] [--sure]`: creates a new nest. Existing nest roots are reported as already initialized and are not repaired. Inside a managed subproject, plain `init` refuses and requires `--sure`.
- `repair [--rc]`: refreshes managed support files for an existing nest.
- `add`: clones a subproject, records its URL, target branch, revision, and clone mode, and updates ignore hygiene.
- `remove`, `move`/`mv`, `config`, `update`, `extract`, and `absorb`: refuse unsafe nested-boundary path operations and reject backslash-separated paths.
- `config`: exposes only allowlisted settings. Currently only `clone-mode` is public, mapping to manifest `clone=full|partial`; unknown keys such as `repo` and unknown values are rejected.
- `snapshot [<path>]`: records clean, reproducible checked-out subproject commits. No argument means all subprojects from anywhere in the nest. `snapshot .` at the root means all subprojects; `snapshot .` inside a managed subproject means that subproject only.
- `restore`: clones missing subprojects, fetches existing subprojects, validates tag/revision drift, restores recorded revisions, and reconciles stale local materialization state.
- `hooks-install` / `hooks-uninstall`: manage only git-nest-owned hooks in all checked-out repositories in the current nest. They can run from anywhere in the nest and do not accept recursive operation.
- `branch-mark`, `branch-unmark`, `branch-list`, and `branch-cleanup`: manage ignored local branch-name memory in `.gitnest-branches`; they do not create, switch, push, or delete Git branches.
- `foreach`, `foreach-modified`, and `foreach-clean`: run commands in checked-out subprojects or selected clean/dirty subsets.
- `clone`: runs `git clone` for a nest repository and automatically runs `restore` unless `--no-restore` is used. It is not a file-copy operation for an existing local checkout.
- `help [command]`: prints the grouped overview without an argument, or command-specific explanation and examples with one command topic. It does not require an existing nest.
- `export`: writes `dir` output with shell file copy, `tar.gz` output with system `tar`, and `zip` output with `python` or `python3` using the standard `zipfile` module.
- `extract`: converts an outer-repository tracked directory into a managed subproject in the current nest.
- `absorb`: converts a managed subproject back into ordinary outer-repository tracked files.
- `doctor`: remote reachability checks use `--timeout <seconds>`, defaulting to `GIT_NEST_DOCTOR_TIMEOUT_SECONDS` or 5 seconds. If the external `timeout` utility is unavailable, git-nest uses a shell watchdog fallback around `git ls-remote`.

Removed public workflow commands are rejected with usage errors: `start`, `upload`, `finalize`, `no-pending`, `foreach-pending`, `cleanup-branches`, `install-hooks`, `remove-hooks`, and `sync`.

## Hooks

Root hooks:

- `post-checkout`: prints concise guidance to run `git-nest restore` inside the nest path when the manifest changes.
- `pre-commit`: attempts a safe snapshot and warns if `.gitnest` changed and needs review/staging.
- `pre-push`: checks reproducibility and warns by default instead of blocking.

Subproject hooks:

- `post-checkout`: snapshots that subproject when the current commit is reproducible.
- `pre-push`: records local push candidates in ignored local state for the root hooks.

Hooks are optional helpers. The manual workflow remains valid without them.

## Nested Projects

Commands that need a nest locate the nearest `.gitnest` by walking to parent directories. Recursive read commands can include nested nests with `--recursive`. Write-side path commands stay within the current nest boundary.

`snapshot --recursive` is the write-side exception that intentionally descends into checked-out nested nests to refresh their manifests.

## Clone Modes And Restore

`clone=full` and `clone=partial` affect how `restore` clones missing subproject checkouts. This clone mode is unrelated to the `git-nest clone` command. Changing the clone mode does not convert an existing checkout in place; remove the checkout and run `restore` when a different materialization mode is desired.

Successful `restore` records materialization state under the outer repository's Git directory. Later restores use this state to move or remove clean stale paths, or to warn when stale paths contain local state that requires manual review or `restore --prune`.

## JSON And Porcelain

`status`, `verify`, `outdated`, `diff`, `foreach-modified`, `foreach-clean`, and `doctor` support machine-readable output where implemented. JSON output is versioned separately through `schemas/git-nest-output-v1.schema.json`.

## Tests

The integration suite creates local bare remotes under `TEST_ROOT`, defaults outside the repository, streams output, writes `test-result.md`, and leaves numbered workspaces for inspection. Current tests cover init/repair, nested init confirmation, add/remove/move, clone/restore modes, stale restore reconciliation, tag drift, snapshot path semantics, branch marks, hooks, status/verify/outdated/diff/log, update modes, export/extract/absorb, completion generation, Git-style invocation, BusyBox compatibility, manifest schema validation, path safety, dry-run behavior, and version output.
