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
- `clone=full|partial|shallow`: optional missing-checkout clone preference; `shallow` creates a shallow clone.
- `depth=<n>`: shallow clone depth when `clone=shallow`; defaults to 1.
- `target_branch=<name>`: branch used by `outdated`, `update --target-head`, and normal tracking.
- `revision=<sha>`: exact reproducible commit.
- `tag=<name>`: optional tag name; requires `revision`.

Only the keys listed above are recognized by git-nest. Unknown keys are preserved as extension data across manifest rewrites, so external tooling can store its own metadata in `.gitnest`; see `docs/MANIFEST.md` for the full format and validation rules.

Subproject paths in the manifest must be safe relative paths inside the nest. Schema validation rejects a manifest whose subproject path is absolute, escapes the nest with `..`, uses a backslash, or names Git-internal files, so no command clones, checks out, or removes outside the nest root.

Manifest rewrites preserve unknown extension keys except for keys owned by the current command. Rewrites are deterministic and protected by `.gitnest.lock`.

Manifest lock acquisition waits up to `GIT_NEST_LOCK_TIMEOUT_SECONDS`, defaulting to 10 seconds, before reporting the lock owner metadata and recovery command.

## Command Guarantees

- `init [--rc] [--sure]`: creates a new nest. Existing nest roots are reported as already initialized and are not repaired. Inside a managed subproject, plain `init` refuses and requires `--sure`. Even with `--sure`, `init` (and `absorb-all`'s auto-init) always refuses when the new nest's own subtree would contain a path already registered as a subproject by an ancestor nest, naming the conflicting ancestor nest, the swallowed path, and the exact manual recipe to resolve it (`detach` the subproject from the ancestor, retry `init` here, then `absorb` it back into the new nest); there is no override for this refusal.
- `tidy [--rc]`: refreshes managed support files for an existing nest, reconciles the managed `.gitignore` block, and prunes stale nest-owned ignore entries (reporting each pruned entry).
- `add`: clones a subproject, records its URL, target branch, revision, and clone mode, and updates ignore hygiene.
- `remove`, `detach`, `move`/`mv`, `config`, `update`, `absorb`, and `inline`: refuse unsafe nested-boundary path operations and reject backslash-separated paths. `add`, `move`, and `absorb` also refuse a path that differs from an existing subproject only by letter case, since that collides on case-insensitive filesystems.
- `config`: exposes only allowlisted settings. Currently only `clone-mode` is public, mapping to manifest `clone=full|partial`; unknown keys such as `repo` and unknown values are rejected.
- `snapshot [<path>]`: records clean, reproducible checked-out subproject commits. No argument means all subprojects from anywhere in the nest. `snapshot .` at the root means all subprojects; `snapshot .` inside a managed subproject means that subproject only.
- `restore`: clones missing subprojects, fetches existing subprojects, validates tag/revision drift, restores recorded revisions, and reconciles stale local materialization state.
- `hooks-install` / `hooks-uninstall`: manage only git-nest-owned hooks in all checked-out repositories in the current nest. They can run from anywhere in the nest and do not accept recursive operation.
- `branch-mark`, `branch-unmark`, `branch-list`, and `branch-cleanup`: manage ignored local branch-name memory in `.gitnest-branches`; they do not create, switch, push, or delete Git branches.
- `foreach`, `foreach-modified`, and `foreach-clean`: run commands in checked-out subprojects or selected clean/dirty subsets. `foreach` supports `--include-root-first`/`--include-root-last` (run on the nest root before or after subprojects) and `--only-nested`/`--no-nested` (filter by whether the subproject is itself a git-nest workspace).
- `clone`: runs `git clone` for a nest repository and automatically runs `restore` unless `--no-restore` is used. It is not a file-copy operation for an existing local checkout.
- `help [command]`: prints the grouped overview without an argument, or command-specific explanation and examples with one command topic. It does not require an existing nest.
- `export`: writes `dir` output with shell file copy, `tar.gz` output with system `tar`, and `zip` output with `python` or `python3` using the standard `zipfile` module.
- `absorb`: brings something already on disk into the nest as a managed subproject, auto-detecting the source. Outer-repository tracked files require a remote URL and support `--branch`, `--clone-mode`, `--preserve-history`, `--push`, `--message`, and `--force`; a standalone nested repository records its own remote and current commit; a Git submodule is converted into a standalone managed subproject by relocating its git directory and removing submodule wiring. It refuses a path that is already a subproject and refuses deeper nested repositories/submodules.
- `inline`: dissolves a managed subproject into the outer repository as ordinary tracked files, discarding the subproject's own Git identity. It is the former `absorb` behavior. Before deleting the subproject's `.git`, and likewise for `absorb --preserve-history` before rewriting history, git-nest makes a transient, self-documenting recovery backup directory (`.gitnest-recovery-<op>-<name>-<timestamp>/` with a `RECOVERY.txt`), ignored on demand via `.git/info/exclude`, removed on success, and left with restore instructions if the conversion is interrupted.
- `detach`: removes a subproject from the manifest but keeps its checkout on disk as a standalone, still-ignored Git repository. It is the former `remove --keep-files` behavior, and it keeps the ignore entry in the managed block so `tidy` can prune it after the directory is moved or removed.
- `remove`/`rm`: removes a subproject from the manifest and deletes its checkout on disk. The retired `--keep-files` flag is rejected with guidance to use `detach`.
- `list`: lists managed subprojects in a stable order with path, repository URL, target branch, revision, tag, checkout state, and reproducibility, in human, `--porcelain`, or `--json`/`--json-pretty` form.
- `tree [--all] [--recursive] [--plain] [--porcelain | --json | --json-pretty]`: displays an ASCII-art tree of the current nest, grouping managed subprojects by shared path prefixes. `--all` also shows `survey`'s own detected-but-unmanaged findings, each marked with its code, without touching state. `--recursive` also descends into nested nests, rendering their own subprojects nested under that branch. `--plain` omits URL and type columns, showing only path and `[code]`. Codes: `[N]` Nest Root, `[M]` Managed, `[C]` Composite (managed + nested nest), `[R]` Unmanaged Repo, `[S]` Unmanaged Submodule, `[G]` Unmanaged Subrepo, `[D]` Unmanaged Detached, `[U]` Unmanaged Nested Nest Root. Every branch uses a single `+--` connector (never a different glyph for the last child of a level) and every entry gets a trailing `/`; continuation columns use `|` or blank spaces per level; no Unicode box-drawing characters. `--porcelain` prints the same 7-column fixed-field rows as the other machine-readable commands; `--json`/`--json-pretty` wrap them in the shared envelope.
- `survey`: scans the current nest for nested Git repositories, submodules, and git-subrepos not listed in `.gitnest`, bounded by `--max-depth` (default 4), pruned by a default set plus repeatable `--exclude` names, and optionally narrowed to specific paths with repeatable `--include`. It reports a kind (submodule, nested repo, git-subrepo, nest root, or a detached former subproject whose path still carries a nest-owned ignore entry) and a suggested next step, and never modifies state or follows symlinks. It replaces `discover`; `discover` is rejected with guidance to use `survey`. A path found underneath a boundary this same scan already classified (a submodule, subrepo, nested repo, or nested nest) is reported with a note that it belongs to that boundary rather than as an independent finding.
- `absorb-all [--sure] [--force-partial] [--dry-run]`: runs the same scan as `survey` (sharing its `--exclude`/`--include`/`--max-depth` flags), then absorbs every detected submodule and nested repo, deepest path first. It never absorbs git-subrepos or subtrees, and never absorbs anything found underneath a boundary the scan already classified. `--sure` confirms initializing a nest here if none exists yet, or confirms creating an intentional nested nest when run inside an existing one (mirroring `init --sure`); without it, either situation is refused. Its auto-init shares `init`'s unconditional refusal (see `init` above) when the new nest's subtree would swallow a path an ancestor nest already manages, even with `--sure`, including in `--dry-run`. On a mid-batch failure, every absorb already performed in the run is rolled back by default (a self-documenting recovery backup, same convention as `inline`/`absorb --preserve-history`); `--force-partial` skips the rollback and keeps whatever succeeded.
- `absorb --subrepo <path> [<remote-url>]` / `absorb --subtree <path> <remote-url>`: explicit, never auto-detected conversions for a git-subrepo (`<path>/.gitrepo`) or a plain subtree-shaped directory (no marker exists, so the remote URL is mandatory). Both are forward-only: the resulting subproject is a fresh single commit, and prior upstream merge/split (subrepo) or subtree history is not carried across. `--subrepo` removes the `.gitrepo` file as part of the conversion. Neither is ever absorbed by `absorb-all`.
- `pull [--recursive] [--sure] [--no-fetch] [--dry-run]`: fast-forwards clean, tracked subprojects to their upstream branch head and snapshots the result. Only subprojects by default; `--sure` also pulls the nest root; `--recursive` additionally descends into nested nests (subprojects that are themselves `.gitnest` workspaces). A dirty, detached-HEAD, or no-upstream-tracking subproject is skipped and reported by path with a concrete fix-it command; a diverged subproject (commits on both sides since the common base) is reported the same way and never force-merged; a network/fetch failure is reported and does not stop the rest of the batch.
- `doctor`: remote reachability checks use `--timeout <seconds>`, defaulting to `GIT_NEST_DOCTOR_TIMEOUT_SECONDS` or 5 seconds. If the external `timeout` utility is unavailable, git-nest uses a shell watchdog fallback around `git ls-remote`.

Removed public workflow commands are rejected with usage errors: `start`, `upload`, `finalize`, `no-pending`, `foreach-pending`, `cleanup-branches`, `install-hooks`, `remove-hooks`, and `sync`. The renamed `extract` command is rejected with guidance to use `absorb`; the renamed `discover` command is rejected with guidance to use `survey`.

## Generator Internals

`git-nest __complete CURSOR_INDEX [--] ARG...` is an internal endpoint used by all generated completion scripts (bash, zsh, fish, yash, powershell). It returns tab-separated completion candidates as TSV records in the format:

`C<TAB>value<TAB>description<TAB>type`

Directives (`D<TAB>directive`) control shell-specific behavior; the engine currently emits `no-file` (suppress native file completion) and `file` (use native file completion).

The engine shares a single case table of all commands and their options, avoiding duplication across shell adapters. Each adapter (a generated script) is a thin translator that calls `__complete` and converts the TSV output to the shell's native completion API.

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

`status`, `verify`, `outdated`, `diff`, `foreach-modified`, `foreach-clean`, `doctor`, `list`, `tree`, `survey`, `absorb`, `absorb-all`, `inline`, `detach`, `remove`, and `pull` support machine-readable output where implemented. The mutating commands (`absorb`, `absorb-all`, `inline`, `detach`, `remove`) report one subproject row per action, and honor `--dry-run` with a `dry_run` flag. `pull` reports one row per subproject outcome (pulled, up-to-date, dirty, detached, no-upstream, diverged, or failed); note that `pull --recursive --json` currently emits one JSON envelope per nest level rather than a single merged envelope. `list` and `doctor` accept `--redact`, which strips credentials embedded in URLs (`scheme://user:token@host` becomes `scheme://***@host`) and replaces the home directory with `~`, so machine output can be shared without leaking secrets or user-specific paths. JSON output is versioned separately through `schemas/git-nest-output-v1.schema.json`.

## Tests

The integration suite creates local bare remotes under `TEST_ROOT`, defaults outside the repository, streams output, writes `run-all-tests-results.md`, captures the full run to `run-all-tests.log` by default, and leaves numbered workspaces for inspection. Current tests cover init/tidy, nested init confirmation, add/remove/move, clone/restore modes, stale restore reconciliation, tag drift, snapshot path semantics, branch marks, hooks, status/verify/outdated/diff/log, update modes, export/absorb (plus legacy extract rejection), completion generation, Git-style invocation, BusyBox compatibility, manifest schema validation, path safety, dry-run behavior, and version output.
