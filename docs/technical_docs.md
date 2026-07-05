# git-lego Technical Notes

`git-lego` 0.7.0 is a small Git orchestration tool for workspaces that contain one outer coordination repository and multiple nested subproject repositories. It borrows the useful workspace idea from Android `repo`, but v0.7 intentionally avoids Gerrit, XML manifests, PR creation, copy/link file features, mirror management, and Android-specific storage layouts.

## Workflow

Create an outer workspace with `git-lego init`, add subprojects with `git-lego add [--clone <full|partial>] <repo> <path>`, start a coordinated branch with `git-lego start XX-123-short-description`, and push subproject branches with `git-lego upload`. Squash-merge or review-gated workflows are handled by making finalization explicit: after subproject PRs land, run `git-lego finalize <subproject> --revision <sha>`, `--tag <tag>`, or `--use-target-head`. Workflows that do not need a separate subproject PR step can use `git-lego upload --finalize` to push and pin changed subproject commits in one step.

Branches created by `git-lego start` are candidate branches. A subproject becomes pending only when `git-lego upload` finds committed work ahead of that subproject's target branch and records a `pending_branch` entry. With `git-lego upload --finalize`, changed subprojects are pushed and recorded directly as finalized revisions instead. Unchanged candidate branches are not pushed, finalized, or treated as pending.

`git-lego start .` and `git-lego snapshot` snapshot local manifest state without creating branches or pushing. They record the current outer branch and pending metadata for clean subprojects with committed work. `snapshot --recursive` applies the same operation to checked-out nested projects.

`git-lego start <branch>` can also bootstrap a non-Git folder. It creates the outer Git repository, `.gitlego`, and the requested branch. Regular files are allowed; existing subdirectories require interactive confirmation or `--sure` in non-interactive scripts.

`git-lego update <subproject>` is the command-line path for moving a clean, non-pending subproject to another recorded version. It can pin the target branch head, an explicit revision, or a tag. `--remote` is an alias for target-head updates, `--no-fetch` uses only local refs, and `--branch` or `--set-branch` changes the subproject's `target_branch` before resolving the selected commit. It refuses dirty and pending subprojects so it does not hide unreviewed work or overwrite pending review state.

`git-lego log` is a read-only project history view. It gathers recent commits from the active project root and checked-out subprojects, sorts them newest-first, labels each commit with its repository path, and never fetches or rewrites history.

`git-lego status --porcelain` is the script-friendly clean-state view. It reports dirty outer/subproject repositories and missing subproject checkouts in stable tab-separated records, and exits zero when inspection succeeds even if output is non-empty.

`git-lego outdated` is a read-only remote check. It uses `git ls-remote` against each subproject's configured repository and target branch, so it can report newer upstream commits without updating local remote-tracking refs, changing checkouts, or rewriting `.gitlego`. `git-lego outdated --porcelain` omits up-to-date and pending subprojects and prints stable records for outdated updates, missing checkouts, and remote query errors.

`git-lego extract <path> <remote-url>` converts an outer-repository tracked directory into a managed subproject at the same path. Default mode creates a fresh subproject commit from current files; `--preserve-history` uses `git-filter-repo` when installed. `git-lego absorb <path>` converts a managed subproject back into ordinary outer-repository files and leaves the remote untouched.

## Manifest

State is stored in `.gitlego` using INI-style sections with mandatory manifest schema `version=1` in `[project]`. Unknown sections and unknown keys are accepted and preserved where practical so extension data can coexist with git-lego state. Optional local configuration is stored in `.gitlego-rc`; `rc` is used in the conventional runtime/configuration sense. Pending subprojects contain `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`. Finalized subprojects contain a pinned `revision`, optionally with `tag`. A subproject is considered pending whenever `pending_branch` is present.

Commands that require a workspace walk upward from the current directory to find the nearest `.gitlego`, then run from that project root. This keeps subproject paths stable even when the command is invoked from deep inside a subproject checkout. If a checked-out subproject is also a project root, it is a nested project; workspace-wide state commands (`status`, `outdated`, `verify`, and `no-pending`) use `--recursive` to include nested projects. `snapshot --recursive` is the only write-side command that intentionally walks downward to refresh checked-out nested project manifests.

Write-side path commands refuse to cross from a parent project into a nested project. Exact tracked subproject paths remain valid from the parent, but paths below a nested project must be handled from that nested project root.

Write-side commands share one upward-only manifest lookup helper, `find_owning_manifest [<path>]`. It resolves an explicit path first, starts from the file's parent directory when a file is passed, and returns the nearest `.gitlego` found while walking toward the filesystem root.

Subprojects may include `clone=full` or `clone=partial`. Missing `clone=` means `full`. Missing `.gitlego-rc` behaves like `[clone] mode=manifest`. When present, `.gitlego-rc` may set `[clone] mode=manifest`, `full`, or `partial`; `full` and `partial` are machine-local overrides. Partial clone uses `git clone --filter=blob:none`; existing checkouts are not converted in place when clone mode changes.

## Limitations

Auto-finalize is conservative and only accepts one commit candidate containing the project ticket key. Provider API lookup is not implemented in v0.7. The `.bat` wrapper is intentionally thin and delegates all behavior to the shell implementation in `bin/`. It is polyglot so it can be called from both `cmd.exe` and sh/bash build contexts, which keeps IDE post-build commands portable across Windows, Linux, and macOS.

## Error Handling

Manifest writes validate required values before mutating state. Pending entries require `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`; finalized entries require a resolved commit `revision`. Missing refs, empty SHAs, malformed subproject entries, invalid clone modes, dirty subprojects during upload, detached changed subprojects, unsafe nested boundary crossings, and failed checkout/push operations exit nonzero with an `Error:` message. `sync` is deliberately different for subproject clone/checkout failures: it attempts every subproject, reports failed paths, and then exits nonzero.

`git-lego verify` is read-only. It validates manifest/config consistency, subproject remotes, resolvable refs, finalized checkout commits, and clone-mode drift. Dirty subprojects are warnings unless they prevent Git inspection. `git-lego outdated` is also read-only, but it contacts remotes and reports upstream movement instead of validating the current checkout. `status`, `verify`, `outdated`, and `no-pending` support JSON output; the shared JSON shape is versioned separately from the manifest schema.

Mutating commands that write `.gitlego` acquire `.gitlego.lock` for the command duration. The lock is an atomic directory containing PID/timestamp metadata and is released through the central exit trap.

## Unsupported Repo Commands

`git-lego` is inspired by Android `repo`, but it does not aim for command parity. v0.7 does not support Gerrit-backed `repo upload`, `repo download`, `repo prune`, XML manifests, `copyfile`, `linkfile`, manifest include/layering features, mirror management, or Android `.repo/` storage behavior.

Android `repo forall` and Git's `git submodule foreach` are useful comparisons. Both are explicit iteration commands: they run a supplied shell command inside each project or submodule. They are not before/after hooks whose position in another command changes execution order.

## Foreach Commands

`git-lego` provides standalone command execution after `git-lego upload`, especially for external provider tools such as Azure CLI:

```sh
git-lego upload
git-lego foreach-pending -- az repos pr create ...
```

Commands:

- `git-lego foreach -- <command> [args...]`: runs the command in every checked-out subproject listed in `.gitlego`.
- `git-lego foreach-pending -- <command> [args...]`: runs the command only in pending subprojects, defined as subproject sections containing `pending_branch=...`.

For this tool, "modified" means pending in the project manifest, not merely a dirty working tree. PR creation remains explicit and external to `upload`; `git-lego` provides the iteration context, while tools such as `az` create the PRs.

The command is executed directly from each subproject directory. Use `sh -c '...'` when shell features such as redirection, pipes, or variable expansion are needed. Each command receives environment variables including `GIT_LEGO_ROOT`, `GIT_LEGO_SUBPROJECT_PATH`, `GIT_LEGO_SUBPROJECT_ABSPATH`, `GIT_LEGO_SUBPROJECT_REPO`, `GIT_LEGO_BRANCH`, `GIT_LEGO_TARGET_BRANCH`, `GIT_LEGO_PENDING_BRANCH`, `GIT_LEGO_BASE_REVISION`, `GIT_LEGO_PUSHED_COMMIT`, `GIT_LEGO_REVISION`, and `GIT_LEGO_TAG`.

Missing subproject checkouts are skipped with a warning. If the command fails in a subproject, iteration stops and `git-lego` returns that exit code.

## Branch Names And Upload

The outer project branch and subproject branches may differ. `upload` pushes each changed subproject's actual current branch and records that branch as `pending_branch`. `upload --finalize` records the pushed commit as `revision` and the branch as `finalized_from_branch` instead. It fails on detached HEAD for changed subprojects and fails if any checked-out subproject has uncommitted changes.

This supports workflows where the outer branch is `XX-123-project`, while subprojects use branch names such as `foo/XX-123` or `bar-XX-123`.

## Git Hooks

Git hooks are opt-in. Use `git-lego install-hooks` or `git-lego start <branch|.> --hooks` to install managed `post-checkout`, `post-commit`, and `pre-push` hooks in the outer repository and every checked-out subproject. Hooks call `git-lego snapshot --quiet`. When managed hooks are already installed in the outer repository, `add` installs them in a newly added subproject and `sync` installs them in newly cloned missing subprojects.

Hooks do not invoke `upload`, because upload pushes branches and records review intent. Those actions remain explicit. `git-lego remove-hooks` removes only managed hooks, and installation refuses unmanaged hooks before writing any managed hook.

## Branch Cleanup

Finalization can preserve cleanup hints for local pending branches. Use `git-lego finalize <subproject> ... --cleanup` to finalize and delete the local pending branch immediately. Use `git-lego cleanup-branches` to delete local branches recorded as cleanup hints later. Cleanup is local-only: it never deletes remote branches or untracked files.

## Test Workspaces

Integration tests use persistent local repositories under `${TMPDIR:-/tmp}/git-lego-test-workspaces` by default so generated outer workspaces, remotes, seeds, and subprojects can be inspected after a run. Use the suite runner:

```sh
sh tests/run-all.sh
```

From `cmd.exe`, use the polyglot batch launcher:

```bat
tests\run-all.bat
```

Both runners remove the test root once at the start of the suite, recreate it, run every `tests/test_*.sh` with stdin closed, and leave all test repositories in numbered folders such as `test_01_auto_finalize/`. The suite prints a blank-line-separated and underlined `TEST nn name` heading for each test, then ends with a summary table containing status, execution time, and executed/passed/failed/skipped totals. Individual tests create their own subdirectory through `tests/helper.sh` and should not delete test output themselves. Test Git commands override line-ending config so local `core.autocrlf` settings do not add CRLF warnings.
