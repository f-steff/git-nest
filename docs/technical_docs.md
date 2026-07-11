# git-nest Technical Notes

## Workflow

Create a nest with `git-nest init`, add subprojects with `git-nest add`, restore recorded files with `git-nest restore`, and record reproducible current subproject commits with `git-nest snapshot`.

Branching, committing, and pushing remain normal Git operations inside each repository. `git-nest branch-mark` can remember useful branch names, but it does not switch repositories.

## Manifest

`.gitnest` records repository URLs and exact revisions. The current manifest does not contain pending review state. Keys from the old pending workflow are schema errors.

## Hooks

Hooks are opt-in through `git-nest hooks-install` and removed with `git-nest hooks-uninstall`. They apply to all checked-out repositories in the current nest and do not recurse into nested nests. Root hooks warn or refresh safe manifest state. Subproject hooks snapshot or record local push candidates. Hooks never push.

## Export Helpers

`export --format dir` uses shell file copying. `export --format tar.gz` requires a system `tar`. `export --format zip` requires `python` or `python3` and uses the standard `zipfile` module. These helpers are not bundled with git-nest; `doctor` reports them as informational checks.

## Error Handling

Manifest writers validate required fields before writing. Dirty subprojects are skipped or rejected depending on command strictness. `restore` attempts every subproject and reports aggregate failures. `verify` and `doctor` are read-only.

## Dry-Run Semantics

`restore --dry-run` and `snapshot --dry-run` print planned changes without writing manifests, cloning, fetching, checking out, or pruning. `freeze`, `extract`, and `absorb` keep their existing dry-run behavior.

## Tests

Run `sh tests/run-all-tests.sh`. The full suite is intentionally integration-heavy and uses local bare remotes.
