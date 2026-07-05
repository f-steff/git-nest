# git-lego Implementation Summary

Version: `0.7.0`

This file is the concise implementation reference for contributors and agents. It describes what the current script does, which state it writes, and which guarantees tests should preserve.

For user-facing guidance, examples, platform setup, CI notes, and comparison with submodules, subtrees, and git-subrepo, read [`../README.md`](../README.md). The README is the manual; this file is the behavior contract.

## Current Scope

`git-lego` is a POSIX-style shell-based multi-repository workspace tool written in `sh`, with a thin polyglot `.bat` wrapper for Windows batch and sh/bash contexts. It runs directly from `bin/` and works as either `git-lego ...` or `git lego ...` when `bin/` is on `PATH`.

`bin/git-lego.bat` is intentionally usable from both `cmd.exe` and `sh`/Bash. This allows one build-hook command to be shared across Windows, Linux, and macOS IDE/project configurations.

Commands that require a workspace walk upward from the current directory until `.gitlego` is found. This allows invocation from the project root, a subdirectory, or deep inside a checked-out subproject.

## Workspace State

A project workspace contains:

- a project root Git repository
- `.gitlego`, tracked by the project root repository
- optional `.gitlego-rc`, local runtime/configuration settings
- `.gitignore`, with subproject paths ignored by the project root repository
- nested standalone Git repositories for subprojects

The project root repository tracks coordination state. Subprojects track source code.

## Manifest Contract

State is stored in an INI-style `.gitlego` file. Manifest schema version `1` is mandatory and documented in [`../MANIFEST.md`](../MANIFEST.md). Unknown sections and unknown keys are accepted and preserved where practical so extension data can coexist with git-lego state.

The `[project]` section must record:

- `version=1`

It may also record:

- `id=<ticket-or-project-id>`
- `branch=<outer-branch>`

Tracked subprojects may contain:

- `repo=<url-or-path>`
- `clone=<full|partial>`
- `target_branch=<branch>`
- `revision=<sha>`

Pending subprojects contain:

- `target_branch=<branch>`
- `pending_branch=<actual-subproject-branch>`
- `base_revision=<sha>`
- `pushed_commit=<sha>`

Finalized subprojects contain:

- `revision=<sha>`
- optional `tag=<tag>`
- optional `finalized_from_branch=<local-cleanup-branch>`

Manifest writes validate required values before mutating `.gitlego`. Empty repository URLs, missing target branches, unresolved refs, empty SHAs, duplicate controlled sections, and malformed subproject sections are hard failures.

## Command Guarantees

- `init [--rc]`: creates the project root repository if needed, plus `.gitlego` and `.gitignore` when missing. `--rc` creates `.gitlego-rc` with default values.
- `add [--clone <full|partial>] <repo> <path>`: clones or records a subproject, ignores the subproject path in the project root, fetches refs, and writes tracked subproject state.
- `status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]`: reports project metadata, subproject state, missing subprojects, and dirty markers. Porcelain mode prints fixed-column records; `--exit-code` returns 1 when dirty or missing rows exist.
- `outdated [--recursive] [--porcelain | --json | --json-pretty]`: queries subproject remotes with `git ls-remote` and reports target-branch commits that differ from the recorded or checked-out state without fetching, checking out files, or rewriting `.gitlego`. It returns 1 when outdated, missing, or error rows are found.
- `diff [--since <ref>] [--stat] [--json | --json-pretty]`: reports subproject commits present in the current checkout but not in recorded manifest revisions. `--since` reads `.gitlego` from an outer-repository ref without checking it out. It returns 1 when differences or read errors are found.
- `config <get|set|list|unset>`: manages manifest-backed subproject settings. Version 0.7.0 supports `clone-mode`, mapped to `clone=<full|partial>`, and writes only the manifest.
- `verify [--recursive] [--json | --json-pretty]`: checks manifest/config consistency without modifying files; structural mismatches return nonzero.
- `log [options]`: shows a read-only, newest-first combined history view across the active project. Supports `--max-count`, `--since`, `--until`, `--subproject`, `--oneline`, and `--recursive`.
- `start <branch|.>`: starts a branch across checked-out repositories or refreshes current state with `.`. Branches are candidate branches until committed subproject work is found by `snapshot` or `upload`.
- `snapshot [--recursive] [--quiet] [--no-fetch] [--base <subproject>=<ref>]`: refreshes local manifest state without pushing and skips dirty subprojects. Non-recursive mode operates only on the current project and notices nested projects; `--recursive` snapshots checked-out nested projects depth-first.
- `upload [--finalize] [--no-fetch] [--base <subproject>=<ref>]`: refuses dirty subprojects, pushes committed subproject branches ahead of target, records pending state by default or finalized state with `--finalize`, commits the manifest when possible, and pushes the project root branch when an origin exists.
- `foreach -- <command>`: runs a command in every checked-out subproject and stops on the first failure.
- `foreach-pending -- <command>`: runs only in subprojects with `pending_branch=...`.
- `foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]`: lists or runs commands in dirty checked-out subprojects.
- `foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]`: lists or runs commands in clean checked-out subprojects.
- `no-pending [--json | --json-pretty]`: reports pending subprojects and exits nonzero while any remain.
- `update <subproject>`: updates one clean, non-pending subproject. Supports `--target-head`, `--remote`, `--revision <sha-or-ref>`, `--tag <tag>`, `--branch <branch>`, `--set-branch <branch>`, and `--no-fetch`.
- `finalize <subproject>`: converts pending subproject state to finalized state using `--revision`, `--tag`, `--use-target-head`, or conservative ticket-key auto-detection. `--cleanup` deletes only the local pending branch.
- `cleanup-branches`: deletes local branches recorded as cleanup hints.
- `install-hooks`: installs managed `post-checkout`, `post-commit`, and `pre-push` hooks in the project root and checked-out subprojects, refusing unmanaged hook overwrite. When the project root has managed hooks, `add` and newly cloned `sync` subprojects inherit them.
- `remove-hooks`: removes only managed hooks.
- `sync [--recursive] [--prune] [--force]`: clones missing subprojects, fetches existing subprojects, restores pending branches where possible, checks out finalized tags or revisions, validates tag/revision drift, reconciles clean stale subproject paths from local materialization state, and attempts every subproject before returning failure for any failed subproject. `--force` only downgrades tag/revision drift to a warning.
- `completion <bash|zsh|fish>`: prints shell completion scripts that complete command names, common command flags, and manifest subproject paths.
- `export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]`: exports tracked subproject working-tree files, `.gitlego`, and `MANIFEST.lock` as a directory, tarball, or zip archive. It refuses dirty subprojects unless `--allow-dirty` is passed.
- `extract <path> <remote-url> [--branch <name>] [--clone-mode <full|partial>] [--preserve-history] [--push] [--message <msg>] [--force] [--dry-run]`: converts an outer-repository tracked directory into a managed subproject at the same path, stages outer file removals plus manifest/ignore changes, and records the extracted commit. Default mode creates a fresh repository from current files. `--preserve-history` requires `git-filter-repo`. Without `--push`, the remote URL is configured but not contacted.
- `absorb <path> [--commit] [--message <msg>] [--dry-run]`: converts a managed subproject back into ordinary outer-repository files, stages manifest/ignore/file changes, and leaves the remote untouched. It commits only with `--commit` or `--message`.
- `remove` / `rm`: removes a subproject from the manifest, optionally keeping files ignored with `--keep-files`.
- `mv`: moves a subproject path or rewrites its manifest URL with `--url`.
- `clone`: clones an outer repository and automatically runs `sync` when `.gitlego` is present.
- `freeze`: pins tracked subprojects to their current checkout commits.
- `version` / `--version`: prints `git-lego 0.7.0`.

## Branch And Version Rules

`start <branch>` switches the project root and checked-out subprojects to candidate branches. Unchanged candidate branches are not recorded as pending, pushed, finalized, or cleaned up.

`start .` is track-current mode. It records the current project root branch and committed subproject work without creating or switching branches.

Subproject branch names may differ from the project root branch. `upload` records each changed subproject's actual current branch as `pending_branch`. `upload --finalize` instead records `revision=<pushed-sha>` and preserves the uploaded branch as `finalized_from_branch` for later local cleanup.

`update --remote` is an alias for `--target-head`. `update --no-fetch` resolves only refs already present in the local subproject checkout. `update --branch` and `--set-branch` retarget `target_branch` before resolving the selected revision. `--branch` is intentionally rejected with `--tag` because tag-pinned finalized state does not record `target_branch`.

Nested projects are subprojects that contain their own `.gitlego`. Commands use the nearest `.gitlego` by default. Workspace-wide state commands (`status`, `outdated`, `verify`, and `no-pending`) include nested projects when `--recursive` is used. `snapshot --recursive` is the only write-side command that intentionally walks downward, and it refreshes checked-out nested projects depth-first.

Write-side path commands refuse to operate below a nested project boundary from the parent project. This applies to manifest/path writers such as `add`, `remove`, `mv`, `config`, `update`, `finalize`, `extract`, and `absorb`. Exact tracked subproject paths remain valid from the parent project.

`extract` requires tracked, committed outer-repository content. Snapshot extraction is in-place and leaves the new subproject checkout at the same path. History-preserving extraction may create `.gitlego-extract-backup/` while rebuilding history and deletes it on success. `--force` on `extract` only overrides staged outer-repository changes under the extracted path. Remote non-empty override is deliberately deferred in 0.7.0.

`absorb` creates `.gitlego-absorb-backup/` before removing nested Git metadata and deletes it on success. It has no `--force` flag; dirty files, unpushed commits, and local-only branch tips are data-safety refusals.

Internal write-side commands resolve the current project with the shared `find_owning_manifest [<path>]` helper, which walks upward from the current directory or explicit path and never walks downward into children.

## Clone Modes

Subproject sections may use `clone=full` or `clone=partial`; missing `clone=` defaults to `full`.

When present, `.gitlego-rc` supports:

```ini
[clone]
mode=manifest
```

Missing `.gitlego-rc` behaves like `mode=manifest`. `mode=manifest` honors each subproject setting. `mode=full` and `mode=partial` force that effective mode for missing subprojects. `sync` does not convert existing checkouts in place.

## Stale Subproject Reconciliation

Successful `sync` records local materialization state under the outer repository Git directory. On later runs, `sync` compares that state with the current manifest. Clean, pushed stale checkouts are moved when exactly one old path and one missing current path share the same repository URL, or removed when no current manifest entry replaces them.

Dirty stale checkouts, untracked files, local-only branch tips, ambiguous same-repo moves, unsafe paths, and non-Git stale directories are left in place with `Warning:` output. `sync --prune` is only for stale paths where plain `sync` suggested it after finding local state; ambiguity and structural uncertainty require manual cleanup.

## Foreach Environment

Porcelain output uses seven fixed tab-separated columns: `code`, `path`, `state`, `target`, `current`, `expected`, and `detail`. JSON output schema version `1` is documented by [`../schemas/git-lego-output-v1.schema.json`](../schemas/git-lego-output-v1.schema.json). Diff rows use code `L`; filtered foreach selection rows use code `F`.

Exit codes are: `0` success, `1` issues found, `2` usage error, `3` precondition failure, `4` lock acquisition failure, and `5` unexpected Git failure.

`foreach`, `foreach-pending`, `foreach-modified`, and `foreach-clean` export these variables when running a command:

- `GIT_LEGO_ROOT`
- `GIT_LEGO_SUBPROJECT_PATH`
- `GIT_LEGO_SUBPROJECT_ABSPATH`
- `GIT_LEGO_SUBPROJECT_REPO`
- `GIT_LEGO_BRANCH`
- `GIT_LEGO_TARGET_BRANCH`
- `GIT_LEGO_PENDING_BRANCH`
- `GIT_LEGO_BASE_REVISION`
- `GIT_LEGO_PUSHED_COMMIT`
- `GIT_LEGO_REVISION`
- `GIT_LEGO_TAG`
- `REPO_PATH`
- `REPO_PROJECT`

Use `sh -c '...'` when shell expansion, redirection, or pipes are needed.

## Error Handling

All user-facing failures should print `Error:` and return nonzero. Recoverable fetch problems may print `Warning:` and continue with local refs. Optional follow-up information may print `Notice:`. Commands should fail before manifest mutation when required state is missing or ambiguous.

Dirty or pending subprojects are protected from commands that would overwrite review state. Failed checkout, push, clone, hook, and cleanup operations must explain what failed and where.

## Tests

The integration suite uses persistent local repositories under `${TMPDIR:-/tmp}/git-lego-test-workspaces` by default. Run:

```sh
sh tests/run-all.sh
```

From `cmd.exe`, run:

```bat
tests\run-all.bat
```

The runner resets the test root at startup, runs each test with stdin closed, prints a blank-line-separated and underlined `TEST nn name` heading, then leaves numbered workspaces such as `test_09_update_command/` for inspection. It ends with a summary table that reports each test's status and execution time plus executed, passed, failed, and skipped totals. Test Git commands override line-ending config so local `core.autocrlf` settings do not add CRLF warnings.

Current tests cover initialization, empty-folder startup, copied-manifest startup, adding subprojects, clone modes, manifest-backed config, project root discovery, verify, status/outdated/diff porcelain and JSON output, outdated remote checks, start/snapshot/upload/finalize/sync, recursive snapshot, stale subproject path reconciliation, project log, nested project boundary refusals, extract/absorb round trips, update modes and negatives, foreach commands and filters, shell completion generation, export formats and deterministic archives, Git-style invocation, optional BusyBox `sh` compatibility, hooks, branch cleanup, graceful failures, and version output.

## Unsupported Repo Features

`git-lego` is not a full Android `repo` replacement. Version `0.7.0` does not support Gerrit integration, automatic PR creation, Android XML manifests, `copyfile`, `linkfile`, manifest include/layering features, Android `.repo/` storage layout, mirror management, or full command parity with Android `repo`.

## Historical Reference

The historical implementation reference was an earlier submodule script, mainly for wrapper structure and shell portability patterns. It is not the current behavior specification.

## License

Copyright (C) 2026 fsteff.

`git-lego` is released under the MIT License (`MIT`).
