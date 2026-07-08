# git-nest Technical Notes

`git-nest` 0.8.0 is a small Git orchestration tool for workspaces that contain one outer coordination repository and multiple nested subproject repositories. It borrows the useful workspace idea from Android `repo`, but keeps the implementation focused on plain Git remotes, a readable manifest, and script-friendly shell behavior.

## Workflow

Create an outer workspace with `git-nest init`, add subprojects with `git-nest add [--clone <full|partial>] <repo> <path>`, start a coordinated branch with `git-nest start XX-123-short-description`, and push subproject branches with `git-nest upload`. Squash-merge or review-gated workflows are handled by making finalization explicit: after subproject PRs land, run `git-nest finalize <subproject> --revision <sha>`, `--tag <tag>`, or `--use-target-head`. Workflows that do not need a separate subproject PR step can use `git-nest upload --finalize` to push and pin changed subproject commits in one step.

Branches created by `git-nest start` are candidate branches. A subproject becomes pending only when `git-nest upload` finds committed work ahead of that subproject's target branch and records a `pending_branch` entry. With `git-nest upload --finalize`, changed subprojects are pushed and recorded directly as finalized revisions instead. Unchanged candidate branches are not pushed, finalized, or treated as pending.

`git-nest start .` and `git-nest snapshot` snapshot local manifest state without creating branches or pushing. They record the current outer branch and pending metadata for clean subprojects with committed work. `snapshot --recursive` applies the same operation to checked-out nested projects.

`git-nest start <branch>` can also bootstrap a non-Git folder. It creates the outer Git repository, `.gitnest`, and the requested branch. Regular files are allowed; existing subdirectories require interactive confirmation or `--sure` in non-interactive scripts.

`git-nest update <subproject>` is the command-line path for moving a clean, non-pending subproject to another recorded version. It can pin the target branch head, an explicit revision, or a tag. `--remote` is an alias for target-head updates, `--no-fetch` uses only local refs, and `--branch` or `--set-branch` changes the subproject's `target_branch` before resolving the selected commit. It refuses dirty and pending subprojects so it does not hide unreviewed work or overwrite pending review state.

`git-nest log` is a read-only project history view. It gathers recent commits from the active project root and checked-out subprojects, sorts them newest-first, labels each commit with its repository path, and never fetches or rewrites history.

`git-nest status --porcelain` is the script-friendly clean-state view. It reports dirty outer/subproject repositories and missing subproject checkouts in stable tab-separated records, and exits zero when inspection succeeds even if output is non-empty.

`git-nest outdated` is a read-only remote check. It uses `git ls-remote` against each subproject's configured repository and target branch, so it can report newer upstream commits without updating local remote-tracking refs, changing checkouts, or rewriting `.gitnest`. `git-nest outdated --porcelain` omits up-to-date and pending subprojects and prints stable records for outdated updates, missing checkouts, and remote query errors.

`git-nest extract <path> <remote-url>` converts an outer-repository tracked directory into a managed subproject at the same path. Default mode creates a fresh subproject commit from current files; `--preserve-history` uses `git-filter-repo` when installed. `git-nest absorb <path>` converts a managed subproject back into ordinary outer-repository files and leaves the remote untouched.

`git-nest doctor` reports environment and workspace-health checks that do not overlap with `verify`: Git version, shell, manifest presence/parseability, lock state, `.gitattributes` guard, backup ignore hints, managed hooks, optional remote reachability, and `git-filter-repo` availability.

## Manifest

State is stored in `.gitnest` using INI-style sections with mandatory manifest schema `version=1` in `[project]`. Unknown sections and unknown keys are accepted and preserved where practical so extension data can coexist with git-nest state. Optional local configuration is stored in `.gitnest-rc`; `rc` is used in the conventional runtime/configuration sense. Pending subprojects contain `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`. Finalized subprojects contain a pinned `revision`, optionally with `tag`. A subproject is considered pending whenever `pending_branch` is present.

Commands that require a workspace walk upward from the current directory to find the nearest `.gitnest`, then run from that project root. This keeps subproject paths stable even when the command is invoked from deep inside a subproject checkout. If a checked-out subproject is also a project root, it is a nested project; workspace-wide state commands (`status`, `outdated`, and `verify`) use `--recursive` to include nested projects. `no-pending` is scoped to the current project. `snapshot --recursive` is the only write-side command that intentionally walks downward to refresh checked-out nested project manifests.

Write-side path commands refuse to cross from a parent project into a nested project. Exact tracked subproject paths remain valid from the parent, but paths below a nested project must be handled from that nested project root.

Write-side path commands require manifest-canonical forward slashes. Backslash-separated paths are refused before normalization so Windows typos do not silently become different manifest entries.

`init` owns a small managed `.gitattributes` block for git-nest files. It removes stale git-nest-owned entries or old managed blocks, then writes canonical attributes for `.gitnest`, `.gitnest-rc`, `bin/git-nest`, `bin/git_nest.sh`, and `bin/git-nest.bat`. Unrelated project attributes are preserved.

Write-side commands share one upward-only manifest lookup helper, `find_owning_manifest [<path>]`. It resolves an explicit path first, starts from the file's parent directory when a file is passed, and returns the nearest `.gitnest` found while walking toward the filesystem root.

Subprojects may include `clone=full` or `clone=partial`. Missing `clone=` means `full`. Missing `.gitnest-rc` behaves like `[clone] mode=manifest`. When present, `.gitnest-rc` may set `[clone] mode=manifest`, `full`, or `partial`; `full` and `partial` are machine-local overrides. Partial clone uses `git clone --filter=blob:none`; existing checkouts are not converted in place when clone mode changes.

## Limitations

Auto-finalize is conservative and only accepts one commit candidate containing the project ticket key. Provider API lookup is not implemented in v0.8. The `.bat` wrapper is intentionally thin and delegates all behavior to the shell implementation in `bin/`. It is polyglot so it can be called from both `cmd.exe` and sh/bash build contexts, which keeps IDE post-build commands portable across Windows, Linux, and macOS.

## Error Handling

Manifest writes validate required values before mutating state. Pending entries require `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`; finalized entries require a resolved commit `revision`. Missing refs, empty SHAs, malformed subproject entries, invalid clone modes, dirty subprojects during upload, detached changed subprojects, unsafe nested boundary crossings, and failed checkout/push operations exit nonzero with an `Error:` message. `upload` preflights every changed subproject before any real push so predictable failures such as a missing `origin` do not leave earlier subprojects pushed or pending. `sync` is deliberately different for subproject clone/checkout failures: it attempts every subproject, reports failed paths, prints recovery guidance, and then exits nonzero.

`git-nest verify` is read-only. It validates manifest/config consistency, subproject remotes, resolvable refs, finalized checkout commits, and clone-mode drift. Dirty subprojects are warnings unless they prevent Git inspection. `git-nest outdated` is also read-only, but it contacts remotes and reports upstream movement instead of validating the current checkout. `status`, `verify`, `outdated`, `diff`, `foreach-modified`, `foreach-clean`, and `no-pending` support JSON output; the shared JSON shape is versioned separately from the manifest schema.

Mutating commands that write `.gitnest` acquire `.gitnest.lock` for the command duration. The lock is an atomic directory containing PID/timestamp metadata and is released through the central exit trap.

### Dry-Run Semantics

`sync --dry-run`, `snapshot --dry-run`, `upload --dry-run`, and `finalize --dry-run` perform normal validation and print planned actions with `[dry-run]` prefixes, but do not write the manifest, push, checkout, clone, delete branches, or run `git fetch`.

Dry-run remote SHA queries use `git ls-remote`, which is read-only and does not update `.git/` remote-tracking refs. If a check genuinely requires a real fetch, dry-run skips that check, reports the affected field as unknown, and notes that the real run would fetch first. A successful dry-run is a planning result, not a guarantee that a later real run will still succeed after remotes or local state change.

### Doctor Semantics

`doctor` human output uses `I`, `W`, and `E` status codes for info, warn, and error. JSON output uses `"info"`, `"warn"`, and `"error"` in each check object. `doctor --exit-code` returns nonzero only when at least one warning or error is present; informational checks never make the command fail. `doctor --offline` skips remote reachability, and `--timeout <seconds>` controls remote `ls-remote` checks when a `timeout` command is available.

## Repo Comparison Notes

`git-nest` is inspired by Android `repo`, but it does not share repo's XML manifest parser, Gerrit assumptions, or `.repo/` storage layout. Compatibility-sensitive differences should be documented in README limitations and covered by tests when they affect observable behavior.

Android `repo forall` and Git's `git submodule foreach` are useful comparisons. Both are explicit iteration commands: they run a supplied shell command inside each project or submodule. They are not before/after hooks whose position in another command changes execution order.

## Foreach Commands

`git-nest` provides standalone command execution after `git-nest upload`, especially for external provider tools such as Azure CLI:

```sh
git-nest upload
git-nest foreach-pending -- az repos pr create ...
```

Commands:

- `git-nest foreach -- <command> [args...]`: runs the command in every checked-out subproject listed in `.gitnest`.
- `git-nest foreach-pending -- <command> [args...]`: runs the command only in pending subprojects, defined as subproject sections containing `pending_branch=...`.
- `git-nest foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]`: lists or runs commands in dirty checked-out subprojects.
- `git-nest foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]`: lists or runs commands in clean checked-out subprojects.

PR creation remains explicit and external to `upload`; `git-nest` provides the iteration context, while tools such as `az` create the PRs. Use `foreach-pending` for manifest-pending review branches, and use `foreach-modified` for dirty working trees.

The command is executed directly from each subproject directory. Use `sh -c '...'` when shell features such as redirection, pipes, or variable expansion are needed. Each command receives environment variables including `GIT_NEST_ROOT`, `GIT_NEST_SUBPROJECT_PATH`, `GIT_NEST_SUBPROJECT_ABSPATH`, `GIT_NEST_SUBPROJECT_REPO`, `GIT_NEST_BRANCH`, `GIT_NEST_TARGET_BRANCH`, `GIT_NEST_PENDING_BRANCH`, `GIT_NEST_BASE_REVISION`, `GIT_NEST_PUSHED_COMMIT`, `GIT_NEST_REVISION`, and `GIT_NEST_TAG`.

Missing subproject checkouts are skipped with a warning. If the command fails in a subproject, iteration stops and `git-nest` returns that exit code.

## Branch Names And Upload

The outer project branch and subproject branches may differ. `upload` pushes each changed subproject's actual current branch and records that branch as `pending_branch`. `upload --finalize` records the pushed commit as `revision` and the branch as `finalized_from_branch` instead. It fails on detached HEAD for changed subprojects and fails if any checked-out subproject has uncommitted changes.

This supports workflows where the outer branch is `XX-123-project`, while subprojects use branch names such as `foo/XX-123` or `bar-XX-123`.

## Git Hooks

Git hooks are opt-in. Use `git-nest install-hooks` or `git-nest start <branch|.> --hooks` to install managed `post-checkout`, `post-commit`, and `pre-push` hooks in the outer repository and every checked-out subproject. Hooks call `git-nest snapshot --quiet`. When managed hooks are already installed in the outer repository, `add` installs them in a newly added subproject and `sync` installs them in newly cloned missing subprojects.

Hooks do not invoke `upload`, because upload pushes branches and records review intent. Those actions remain explicit. `git-nest remove-hooks` removes only managed hooks, and installation refuses unmanaged hooks before writing any managed hook.

## Branch Cleanup

Finalization can preserve cleanup hints for local pending branches. Use `git-nest finalize <subproject> ... --cleanup` to finalize and delete the local pending branch immediately. Use `git-nest cleanup-branches` to delete local branches recorded as cleanup hints later. Cleanup is local-only: it never deletes remote branches or untracked files.

## Test Workspaces

Integration tests use persistent local repositories under `${TMPDIR:-/tmp}/git-nest-test-workspaces` by default so generated outer workspaces, remotes, seeds, and subprojects can be inspected after a run. Use the suite runner:

```sh
sh tests/run-all-tests.sh
```

From `cmd.exe`, use the polyglot batch launcher:

```bat
tests\run-all-tests.bat
```

Both runners remove the test root once at the start of the suite, recreate it, run every `tests/test_*.sh` with stdin closed, stream each test's output while capturing a per-test log, and leave all test repositories in numbered folders such as `test_01_command_finalize_auto_no_pending/`. The full suite is long-running and may exceed 10 minutes. The suite prints a blank-line-separated and underlined `TEST nn name` heading for each test, appends an ignored root-level `test-result.md` as each test completes, then ends with a summary table containing status, execution time, total execution time, and executed/passed/failed/skipped totals. Individual tests create their own subdirectory through `tests/helper.sh` and should not delete test output themselves. Test Git commands override line-ending config so local `core.autocrlf` settings do not add CRLF warnings.

Test files are organized around feature prefixes: `test_command_*`, `test_command_option_*`, `test_symmetry_*`, `test_workflow_*`, `test_contract_*`, and `test_platform_*`. New tests must not use milestone labels such as `wave` or `vawe`. Tests should use the shared narration helpers to explain the scenario, show important commands, state expected results in plain English, and summarize results while keeping full command output captured for diagnostics. Unexpected assertion results should include `UNEXPECTED RESULT:`. The runner fails any active test that produces no output for more than `TEST_WATCHDOG_SECONDS` seconds, default 180, and stops the suite after the first hung test.
