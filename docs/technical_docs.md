# git-nest Technical Notes

## Workflow

Create a nest with `git-nest init`, add subprojects with `git-nest add`, restore recorded files with `git-nest restore`, and record reproducible current subproject commits with `git-nest snapshot`.

Branching, committing, and pushing remain normal Git operations inside each repository. `git-nest branch-mark` can remember useful branch names, but it does not switch repositories.

## Manifest

`.gitnest` records repository URLs and exact revisions. The current manifest does not contain pending review state. Keys from the old pending workflow are schema errors.

## Managed .gitignore Block

git-nest keeps its ignore rules inside a self-healing `# BEGIN git-nest ignores` / `# END git-nest ignores` block. The block holds constant hygiene rules (`**/.git`, `**/.git/`, `.gitnest-branches`, `.gitnest-push-candidates`) plus one canonical `path/` line per managed subproject. User-authored ignore lines outside the block are preserved in order. `add`, `absorb`, `move`, `remove`, and `inline` update the block, and `init`/`repair` reconcile it: nest-owned entries a user moved or duplicated outside the block are pulled back in and deduped. `repair` also prunes stale nest-owned entries whose path is neither a managed subproject nor present on disk (the orphan left after a `detach`ed repository is physically removed), and `doctor` warns when such stale entries exist.

## Conversion Backups

The destructive conversions (`inline`, and `absorb --preserve-history`) first create a self-documenting recovery backup directory named `.gitnest-recovery-<operation>-<name>-<timestamp>/` containing a `RECOVERY.txt` with restore and cleanup steps. git-nest removes the backup automatically on success. While the conversion runs, the directory is ignored on demand through the repo-local `.git/info/exclude` file (never the committed `.gitignore`), so `git status` stays clean and no transient rule is ever committed. If a conversion is interrupted, the backup remains: the command's error message and `RECOVERY.txt` explain how to restore, and `git-nest doctor` reports the leftover so it is easy to discover. `discover` prunes `.gitnest-recovery-*` directories from its scan.

## Hooks

Hooks are opt-in through `git-nest hooks-install` and removed with `git-nest hooks-uninstall`. They apply to all checked-out repositories in the current nest and do not recurse into nested nests. Root hooks warn or refresh safe manifest state. Subproject hooks snapshot or record local push candidates. Hooks never push.

## Export Helpers

`export --format dir` uses shell file copying. `export --format tar.gz` requires a system `tar`. `export --format zip` requires `python` or `python3` and uses the standard `zipfile` module. These helpers are not bundled with git-nest; `doctor` reports them as informational checks.

## Filesystem And Concurrency

Manifest writes are serialized with a `.gitnest.lock` directory acquired with a bounded wait (`GIT_NEST_LOCK_TIMEOUT_SECONDS`, default 10). An EXIT/INT/TERM trap releases the lock, so an interrupted or failed command never leaves the workspace locked, and the timeout message reports the holding PID and a removal command. Temporary files use unique `mktemp` names next to their target, so simultaneous operations never share a predictable temp path.

Path safety does not rely on prefix string matching. User-supplied paths are validated as safe relative paths (no absolute paths, no `..` escape, no backslashes, no Git-internal names), and the same validation runs on subproject paths read from the manifest, so a crafted `.gitnest` cannot make a command clone, check out, or remove outside the nest root. `add`, `move`, and `absorb` additionally refuse a path that differs from an existing subproject only by letter case, preventing collisions on case-insensitive filesystems (Windows, macOS).

## Machine-Readable Diagnostics

Inspection and mutating commands emit JSON on the versioned `schemas/git-nest-output-v1.schema.json` contract so tools never parse prose, tables, icons, or logo text. `list` and `doctor` accept `--redact` to strip credentials from URLs and the home directory from paths in their output when the result may be shared or logged.

## Error Handling

Manifest writers validate required fields before writing. Dirty subprojects are skipped or rejected depending on command strictness. `restore` attempts every subproject and reports aggregate failures. `verify` and `doctor` are read-only.

## Dry-Run Semantics

`restore --dry-run` and `snapshot --dry-run` print planned changes without writing manifests, cloning, fetching, checking out, or pruning. `freeze`, `absorb`, `inline`, `detach`, and `remove` also support `--dry-run` and report the planned change without writing.

## Tests

Run `sh tests/run-all-tests.sh`. The full suite is intentionally integration-heavy and uses local bare remotes.
