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

## Error Handling

Manifest writers validate required fields before writing. Dirty subprojects are skipped or rejected depending on command strictness. `restore` attempts every subproject and reports aggregate failures. `verify` and `doctor` are read-only.

## Dry-Run Semantics

`restore --dry-run` and `snapshot --dry-run` print planned changes without writing manifests, cloning, fetching, checking out, or pruning. `freeze`, `absorb`, `inline`, `detach`, and `remove` also support `--dry-run` and report the planned change without writing.

## Tests

Run `sh tests/run-all-tests.sh`. The full suite is intentionally integration-heavy and uses local bare remotes.
