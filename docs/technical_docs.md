# git-nest Technical Notes

## Workflow

Create a nest with `git-nest init`, add subprojects with `git-nest add`, restore recorded files with `git-nest restore`, and record reproducible current subproject commits with `git-nest snapshot`.

Branching, committing, and pushing remain normal Git operations inside each repository. `git-nest branch-mark` can remember useful branch names, but it does not switch repositories.

`git-nest survey` (read-only) and `git-nest absorb-all` (mutating) help migrate an existing tree of nested repositories and submodules into a nest in one pass: `survey` reports what is out there, and `absorb-all` reuses that same scan to absorb every detected submodule and nested repo, deepest path first, rolling back the whole batch by default on a mid-batch failure. Git-subrepos (`.gitrepo`) and subtrees are never touched by either; they require the explicit `absorb --subrepo`/`absorb --subtree` conversions. `git-nest pull` fast-forwards clean, tracked subprojects to their upstream branch heads and snapshots the result, reporting (never forcing past) dirty, detached, no-upstream, or diverged subprojects by path.

## Manifest

`.gitnest` records repository URLs and exact revisions. The current manifest does not contain pending review state. Keys from the old pending workflow are schema errors.

## Managed .gitignore Block

git-nest keeps its ignore rules inside a self-healing `# BEGIN git-nest ignores` / `# END git-nest ignores` block. The block holds constant hygiene rules (`**/.git`, `**/.git/`, `.gitnest-branches`, `.gitnest-push-candidates`) plus one canonical `path/` line per managed subproject. User-authored ignore lines outside the block are preserved in order. `add`, `absorb`, `move`, `remove`, and `inline` update the block, and `init`/`repair` reconcile it: nest-owned entries a user moved or duplicated outside the block are pulled back in and deduped. `repair` also prunes stale nest-owned entries whose path is neither a managed subproject nor present on disk (the orphan left after a `detach`ed repository is physically removed), and `doctor` warns when such stale entries exist.

## Conversion Backups

The destructive conversions (`inline`, `absorb --preserve-history`, and `absorb-all`) first create a self-documenting recovery backup directory named `.gitnest-recovery-<operation>-<name>-<timestamp>/` containing a `RECOVERY.txt` with restore and cleanup steps. git-nest removes the backup automatically on success. While the conversion runs, the directory is ignored on demand through the repo-local `.git/info/exclude` file (never the committed `.gitignore`), so `git status` stays clean and no transient rule is ever committed. If a conversion is interrupted, the backup remains: the command's error message and `RECOVERY.txt` explain how to restore, and `git-nest doctor` reports the leftover so it is easy to discover. `survey` prunes `.gitnest-recovery-*` directories from its scan. `absorb-all` uses one recovery backup for its whole batch: a full copy of each item's pre-absorb directory plus the outer `.gitnest`/`.gitignore`/`.gitmodules` files, so a mid-batch failure can restore everything absorbed so far in one step (`--force-partial` keeps the successfully-absorbed items instead and skips the rollback).

## Hooks

Hooks are opt-in through `git-nest hooks-install` and removed with `git-nest hooks-uninstall`. They apply to all checked-out repositories in the current nest and do not recurse into nested nests. Root hooks warn or refresh safe manifest state. Subproject hooks snapshot or record local push candidates. Hooks never push.

## Export Helpers

`export --format dir` uses shell file copying. `export --format tar.gz` requires a system `tar`. `export --format zip` requires `python` or `python3` and uses the standard `zipfile` module. These helpers are not bundled with git-nest; `doctor` reports them as informational checks.

## Filesystem And Concurrency

Manifest writes are serialized with a `.gitnest.lock` directory acquired with a bounded wait (`GIT_NEST_LOCK_TIMEOUT_SECONDS`, default 10). An EXIT/INT/TERM trap releases the lock, so an interrupted or failed command never leaves the workspace locked, and the timeout message reports the holding PID and a removal command. Temporary files use unique `mktemp` names next to their target, so simultaneous operations never share a predictable temp path.

Path safety does not rely on prefix string matching. User-supplied paths are validated as safe relative paths (no absolute paths, no `..` escape, no backslashes, no Git-internal names), and the same validation runs on subproject paths read from the manifest, so a crafted `.gitnest` cannot make a command clone, check out, or remove outside the nest root. `add`, `move`, and `absorb` additionally refuse a path that differs from an existing subproject only by letter case, preventing collisions on case-insensitive filesystems (Windows, macOS).

`init --sure` and `absorb-all`'s auto-init also refuse, unconditionally, when the new nest's own subtree would contain a path already registered as a subproject by an ancestor nest -- the mirror image of a new subproject being created inside an existing one. This can only happen if a directory that is an ancestor of an already-registered deep subproject is later, retroactively, given its own Git repository; `absorb` itself cannot hit it (`assert_no_deeper_repos` and `assert_path_not_containing_nested_project` already guard every absorb path). The check walks the full ancestor manifest chain, not just the nearest one, and the refusal names the conflicting ancestor nest, the swallowed path, and the exact manual recipe to resolve it: `detach` the subproject from the ancestor, retry `init` here, then `absorb` it back into the new nest.

## Machine-Readable Diagnostics

Inspection and mutating commands emit JSON on the versioned `schemas/git-nest-output-v1.schema.json` contract so tools never parse prose, tables, icons, or logo text. `list` and `doctor` accept `--redact` to strip credentials from URLs and the home directory from paths in their output when the result may be shared or logged.

## Error Handling

Manifest writers validate required fields before writing. Dirty subprojects are skipped or rejected depending on command strictness. `restore` attempts every subproject and reports aggregate failures. `verify` and `doctor` are read-only.

## Dry-Run Semantics

`restore --dry-run` and `snapshot --dry-run` print planned changes without writing manifests, cloning, fetching, checking out, or pruning. `freeze`, `absorb` (including `--subrepo`/`--subtree`), `absorb-all`, `inline`, `detach`, `remove`, and `pull` also support `--dry-run` and report the planned change without writing. `absorb-all --dry-run` never runs the init step either, even when the scanned directory is not yet a nest.

## Worktree Compatibility

git-nest is transparent to Git worktrees. Each linked worktree created with `git worktree add` has its own independent manifest checkout, subproject checkouts, and materialized state. No special setup or configuration is needed.

The materialized state file (`<git-path>/git-nest/subprojects`) is resolved through `git rev-parse --git-path`, which Git automatically points to the worktree's private storage under `.git/worktrees/<name>/` instead of the shared `.git/`. This ensures that `restore`, `snapshot`, `status`, and all other commands operate on the correct worktree-local state without cross-contamination.

### Per-worktree vs shared components

| Component | Scope | Notes |
|---|---|---|
| `.gitnest` manifest | Per-worktree | Each worktree has its own checkout of the manifest; changes in one worktree do not affect another until committed and merged |
| Subproject checkouts | Per-worktree | Cloned independently per worktree; disk usage depends on Git's `--reference` or `--shared` options |
| Materialized state (`git-nest/subprojects`) | Per-worktree | Resolved through `--git-path`, landing in the worktree's private git dir |
| `.gitignore` managed block | Per-worktree | Each worktree edits its own checkout of `.gitignore` |
| `.gitnest.lock` | Per-worktree | Lock is local to the current worktree |
| Git object store | Shared | Underlying objects and refs are shared through Git's object store |
| Subproject remote objects | Shared | Cloned subprojects share the Git object store of the containing worktree |

Running `git-nest` commands from a linked worktree affects only that worktree's state. Committing and pushing changes to `.gitnest` follows normal Git worktree practices: commit from the worktree, then merge or rebase across branches.

## Tests

Run `sh tests/run-all-tests.sh`. The full suite is intentionally integration-heavy and uses local bare remotes.
