# git-stack Technical Notes

`git-stack` 0.4.1 is a small Git orchestration tool for workspaces that contain one outer coordination repository and multiple nested module repositories. It borrows the useful workspace idea from Android `repo`, but v0.4 intentionally avoids Gerrit, XML manifests, PR creation, copy/link file features, mirror management, and Android-specific storage layouts.

## Workflow

Create an outer workspace with `git-stack init`, add modules with `git-stack add [--clone <full|partial>] <repo> <path>`, start a coordinated branch with `git-stack start XX-123-short-description`, and push module branches with `git-stack upload`. Squash-merge or review-gated workflows are handled by making finalization explicit: after module PRs land, run `git-stack finalize <module> --revision <sha>`, `--tag <tag>`, or `--use-target-head`. Workflows that do not need a separate module PR step can use `git-stack upload --finalize` to push and pin changed module commits in one step.

Branches created by `git-stack start` are candidate branches. A module becomes pending only when `git-stack upload` finds committed work ahead of that module's target branch and records a `pending_branch` entry. With `git-stack upload --finalize`, changed modules are pushed and recorded directly as finalized revisions instead. Unchanged candidate branches are not pushed, finalized, or treated as pending.

`git-stack start .` and `git-stack refresh` refresh local manifest state without creating branches or pushing. They record the current outer branch and pending metadata for clean modules with committed work.

`git-stack start <branch>` can also bootstrap a non-Git folder. It creates the outer Git repository, `.stack`, and the requested branch. Regular files are allowed; existing subdirectories require interactive confirmation or `--sure` in non-interactive scripts.

`git-stack update <module>` is the command-line path for moving a clean, non-pending stack module to another recorded version. It can pin the target branch head, an explicit revision, or a tag. `--remote` is an alias for target-head updates, `--no-fetch` uses only local refs, and `--branch` or `--set-branch` changes the module's `target_branch` before resolving the selected commit. It refuses dirty and pending modules so it does not hide unreviewed work or overwrite pending review state.

`git-stack log` is a read-only stack history view. It gathers recent commits from the active stack root and checked-out modules, sorts them newest-first, labels each commit with its repository path, and never fetches or rewrites history.

`git-stack status --porcelain` is the script-friendly clean-state view. It reports dirty outer/module repositories and missing module checkouts in stable tab-separated records, and exits zero when inspection succeeds even if output is non-empty.

`git-stack available` is a read-only remote availability check. It uses `git ls-remote` against each module's configured repository and target branch, so it can report newer upstream commits without updating local remote-tracking refs, changing checkouts, or rewriting `.stack`. `git-stack available --porcelain` omits up-to-date and pending modules and prints stable records for available updates, missing checkouts, and remote availability errors.

## Manifest

State is stored in `.stack` using INI-style sections. Optional local configuration is stored in `.stack-rc`; `rc` is used in the conventional runtime/configuration sense. Pending modules contain `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`. Finalized modules contain a pinned `revision`, optionally with `tag`. A module is considered pending whenever `pending_branch` is present.

Commands that require a workspace walk upward from the current directory to find the nearest `.stack`, then run from that stack root. This keeps module paths stable even when the command is invoked from deep inside a module checkout. If a checked-out module is also a stack root, it is a nested stack; `status`, `available`, `verify`, `sync`, and `log` print `Notice:` unless `--recursive` is used to include nested stacks.

Modules may include `clone=full` or `clone=partial`. Missing `clone=` means `full`. Missing `.stack-rc` behaves like `[clone] mode=manifest`. When present, `.stack-rc` may set `[clone] mode=manifest`, `full`, or `partial`; `full` and `partial` are machine-local overrides. Partial clone uses `git clone --filter=blob:none`; existing checkouts are not converted in place when clone mode changes.

## Limitations

Auto-finalize is conservative and only accepts one commit candidate containing the stack ticket key. Provider API lookup is not implemented in v0.4. The `.bat` wrapper is intentionally thin and delegates all behavior to the shell implementation in `bin/`. It is polyglot so it can be called from both `cmd.exe` and sh/bash build contexts, which keeps IDE post-build commands portable across Windows, Linux, and macOS.

## Error Handling

Manifest writes validate required values before mutating state. Pending entries require `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`; finalized entries require a resolved commit `revision`. Missing refs, empty SHAs, malformed module entries, invalid clone modes, dirty modules during upload, detached changed modules, and failed checkout/push operations exit nonzero with an `Error:` message. `sync` is deliberately different for module clone/checkout failures: it attempts every module, reports failed paths, and then exits nonzero.

`git-stack verify` is read-only. It validates manifest/config consistency, module remotes, resolvable refs, finalized checkout commits, and clone-mode drift. Dirty modules are warnings unless they prevent Git inspection. `git-stack available` is also read-only, but it contacts remotes and reports availability instead of validating the current checkout.

## Unsupported Repo Commands

`git-stack` is inspired by Android `repo`, but it does not aim for command parity. v0.4 does not support Gerrit-backed `repo upload`, `repo download`, `repo prune`, XML manifests, `copyfile`, `linkfile`, manifest include/layering features, mirror management, or Android `.repo/` storage behavior.

Android `repo forall` and Git's `git submodule foreach` are useful comparisons. Both are explicit iteration commands: they run a supplied shell command inside each project or submodule. They are not before/after hooks whose position in another command changes execution order.

## Foreach Commands

`git-stack` provides standalone command execution after `git-stack upload`, especially for external provider tools such as Azure CLI:

```sh
git-stack upload
git-stack foreach-modified -- az repos pr create ...
```

Commands:

- `git-stack foreach -- <command> [args...]`: runs the command in every checked-out module listed in `.stack`.
- `git-stack foreach-modified -- <command> [args...]`: runs the command only in pending modules, defined as module sections containing `pending_branch=...`.

For this tool, "modified" means pending in the stack manifest, not merely a dirty working tree. PR creation remains explicit and external to `upload`; `git-stack` provides the iteration context, while tools such as `az` create the PRs.

The command is executed directly from each module directory. Use `sh -c '...'` when shell features such as redirection, pipes, or variable expansion are needed. Each command receives environment variables including `GIT_STACK_ROOT`, `GIT_STACK_MODULE_PATH`, `GIT_STACK_MODULE_ABSPATH`, `GIT_STACK_MODULE_REPO`, `GIT_STACK_BRANCH`, `GIT_STACK_TARGET_BRANCH`, `GIT_STACK_PENDING_BRANCH`, `GIT_STACK_BASE_REVISION`, `GIT_STACK_PUSHED_COMMIT`, `GIT_STACK_REVISION`, and `GIT_STACK_TAG`.

Missing module checkouts are skipped with a warning. If the command fails in a module, iteration stops and `git-stack` returns that exit code.

## Branch Names And Upload

The outer stack branch and module branches may differ. `upload` pushes each changed module's actual current branch and records that branch as `pending_branch`. `upload --finalize` records the pushed commit as `revision` and the branch as `finalized_from_branch` instead. It fails on detached HEAD for changed modules and fails if any checked-out module has uncommitted changes.

This supports workflows where the outer branch is `XX-123-stack`, while modules use branch names such as `foo/XX-123` or `bar-XX-123`.

## Git Hooks

Git hooks are opt-in. Use `git-stack install-hooks` or `git-stack start <branch|.> --hooks` to install managed `post-checkout`, `post-commit`, and `pre-push` hooks in the outer repository and every checked-out module. Hooks call `git-stack refresh --quiet`. When managed hooks are already installed in the outer repository, `add` installs them in a newly added module and `sync` installs them in newly cloned missing modules.

Hooks do not invoke `upload`, because upload pushes branches and records review intent. Those actions remain explicit. `git-stack remove-hooks` removes only managed hooks, and installation refuses unmanaged hooks before writing any managed hook.

## Branch Cleanup

Finalization can preserve cleanup hints for local pending branches. Use `git-stack finalize <module> ... --cleanup` to finalize and delete the local pending branch immediately. Use `git-stack cleanup-branches` to delete local branches recorded as cleanup hints later. Cleanup is local-only: it never deletes remote branches or untracked files.

## Test Workspaces

Integration tests use persistent local repositories under `${TMPDIR:-/tmp}/git-stack-test-workspaces` by default so generated outer workspaces, remotes, seeds, and modules can be inspected after a run. Use the suite runner:

```sh
sh tests/run-all.sh
```

From `cmd.exe`, use the polyglot batch launcher:

```bat
tests\run-all.bat
```

Both runners remove the test root once at the start of the suite, recreate it, run every `tests/test_*.sh` with stdin closed, and leave all test repositories in numbered folders such as `test_01_auto_finalize/`. The suite prints a blank-line-separated and underlined `TEST nn name` heading for each test, then ends with a summary table containing status, execution time, and executed/passed/failed/skipped totals. Individual tests create their own subdirectory through `tests/helper.sh` and should not delete test output themselves. Test Git commands override line-ending config so local `core.autocrlf` settings do not add CRLF warnings.
