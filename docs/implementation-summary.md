# git-stack Implementation Summary

Version: `0.4.1`

This file is the concise implementation reference for contributors and agents. It describes what the current script does, which state it writes, and which guarantees tests should preserve.

For user-facing guidance, examples, platform setup, CI notes, and comparison with submodules, subtrees, and git-subrepo, read [`../README.md`](../README.md). The README is the manual; this file is the behavior contract.

## Current Scope

`git-stack` is a POSIX-style shell-based multi-repository workspace tool written in `sh`, with a thin polyglot `.bat` wrapper for Windows batch and sh/bash contexts. It runs directly from `bin/` and works as either `git-stack ...` or `git stack ...` when `bin/` is on `PATH`.

`bin/git-stack.bat` is intentionally usable from both `cmd.exe` and `sh`/Bash. This allows one build-hook command to be shared across Windows, Linux, and macOS IDE/project configurations.

Commands that require a workspace walk upward from the current directory until `.stack` is found. This allows invocation from the stack root, a subdirectory, or deep inside a checked-out stack module.

## Workspace State

A stack workspace contains:

- a stack root Git repository
- `.stack`, tracked by the stack root repository
- optional `.stack-rc`, local runtime/configuration settings
- `.gitignore`, with stack module paths ignored by the stack root repository
- nested standalone Git repositories for stack modules

The stack root repository tracks coordination state. Stack modules track source code.

## Manifest Contract

State is stored in an INI-style `.stack` file.

The `[stack]` section may record:

- `id=<ticket-or-stack-id>`
- `branch=<outer-branch>`

Tracked modules may contain:

- `repo=<url-or-path>`
- `clone=<full|partial>`
- `target_branch=<branch>`
- `revision=<sha>`

Pending modules contain:

- `target_branch=<branch>`
- `pending_branch=<actual-module-branch>`
- `base_revision=<sha>`
- `pushed_commit=<sha>`

Finalized modules contain:

- `revision=<sha>`
- optional `tag=<tag>`
- optional `finalized_from_branch=<local-cleanup-branch>`

Manifest writes validate required values before mutating `.stack`. Empty repository URLs, missing target branches, unresolved refs, and empty SHAs are hard failures.

## Command Guarantees

- `init [--rc]`: creates the stack root repository if needed, plus `.stack` and `.gitignore` when missing. `--rc` creates `.stack-rc` with default values.
- `add [--clone <full|partial>] <repo> <path>`: clones or records a stack module, ignores the module path in the stack root, fetches refs, and writes tracked module state.
- `status [--recursive] [--porcelain]`: reports stack metadata, module state, missing modules, and dirty markers. Porcelain mode prints stable tab-separated dirty and missing records for scripts.
- `available [--recursive] [--porcelain]`: queries module remotes with `git ls-remote` and reports target-branch commits that differ from the recorded or checked-out state without fetching, checking out files, or rewriting `.stack`. Porcelain mode prints stable records only for available updates, missing checkouts, and availability errors.
- `verify [--recursive]`: checks manifest/config consistency without modifying files; structural mismatches return nonzero.
- `log [options]`: shows a read-only, newest-first combined history view across the active stack. Supports `--max-count`, `--since`, `--until`, `--module`, `--oneline`, and `--recursive`.
- `start <branch|.>`: starts a branch across checked-out repositories or refreshes current state with `.`. Branches are candidate branches until committed module work is found by `refresh` or `upload`.
- `refresh [--quiet]`: refreshes local manifest state without pushing and skips dirty modules.
- `upload [--finalize]`: refuses dirty modules, pushes committed module branches ahead of target, records pending state by default or finalized state with `--finalize`, commits the manifest when possible, and pushes the stack root branch when an origin exists.
- `foreach -- <command>`: runs a command in every checked-out module and stops on the first failure.
- `foreach-modified -- <command>`: runs only in modules with `pending_branch=...`.
- `check`: reports pending modules and exits nonzero while any remain.
- `update <module>`: updates one clean, non-pending module. Supports `--target-head`, `--remote`, `--revision <sha-or-ref>`, `--tag <tag>`, `--branch <branch>`, `--set-branch <branch>`, and `--no-fetch`.
- `finalize <module>`: converts pending module state to finalized state using `--revision`, `--tag`, `--use-target-head`, or conservative ticket-key auto-detection. `--cleanup` deletes only the local pending branch.
- `cleanup-branches`: deletes local branches recorded as cleanup hints.
- `install-hooks`: installs managed `post-checkout`, `post-commit`, and `pre-push` hooks in the stack root and checked-out modules, refusing unmanaged hook overwrite. When the stack root has managed hooks, `add` and newly cloned `sync` modules inherit them.
- `remove-hooks`: removes only managed hooks.
- `sync [--recursive]`: clones missing modules, fetches existing modules, restores pending branches where possible, and checks out finalized tags or revisions. It attempts every module before returning failure for any failed module.
- `version` / `--version`: prints `git-stack 0.4.1`.

## Branch And Version Rules

`start <branch>` switches the stack root and checked-out modules to candidate branches. Unchanged candidate branches are not recorded as pending, pushed, finalized, or cleaned up.

`start .` is track-current mode. It records the current stack root branch and committed module work without creating or switching branches.

Module branch names may differ from the stack root branch. `upload` records each changed module's actual current branch as `pending_branch`. `upload --finalize` instead records `revision=<pushed-sha>` and preserves the uploaded branch as `finalized_from_branch` for later local cleanup.

`update --remote` is an alias for `--target-head`. `update --no-fetch` resolves only refs already present in the local module checkout. `update --branch` and `--set-branch` retarget `target_branch` before resolving the selected revision. `--branch` is intentionally rejected with `--tag` because tag-pinned finalized state does not record `target_branch`.

Nested stacks are stack modules that contain their own `.stack`. Commands use the nearest `.stack` by default. `status`, `available`, `verify`, `sync`, and `log` print `Notice:` when they discover nested stacks without `--recursive`; with `--recursive`, they include nested stacks depth-first.

## Clone Modes

Module sections may use `clone=full` or `clone=partial`; missing `clone=` defaults to `full`.

When present, `.stack-rc` supports:

```ini
[clone]
mode=manifest
```

Missing `.stack-rc` behaves like `mode=manifest`. `mode=manifest` honors each module setting. `mode=full` and `mode=partial` force that effective mode for missing modules. `sync` does not convert existing checkouts in place.

## Foreach Environment

`foreach` and `foreach-modified` export:

- `GIT_STACK_ROOT`
- `GIT_STACK_MODULE_PATH`
- `GIT_STACK_MODULE_ABSPATH`
- `GIT_STACK_MODULE_REPO`
- `GIT_STACK_BRANCH`
- `GIT_STACK_TARGET_BRANCH`
- `GIT_STACK_PENDING_BRANCH`
- `GIT_STACK_BASE_REVISION`
- `GIT_STACK_PUSHED_COMMIT`
- `GIT_STACK_REVISION`
- `GIT_STACK_TAG`
- `REPO_PATH`
- `REPO_PROJECT`

Use `sh -c '...'` when shell expansion, redirection, or pipes are needed.

## Error Handling

All user-facing failures should print `Error:` and return nonzero. Recoverable fetch problems may print `Warning:` and continue with local refs. Optional follow-up information may print `Notice:`. Commands should fail before manifest mutation when required state is missing or ambiguous.

Dirty or pending modules are protected from commands that would overwrite review state. Failed checkout, push, clone, hook, and cleanup operations must explain what failed and where.

## Tests

The integration suite uses persistent local repositories under `${TMPDIR:-/tmp}/git-stack-test-workspaces` by default. Run:

```sh
sh tests/run-all.sh
```

From `cmd.exe`, run:

```bat
tests\run-all.bat
```

The runner resets the test root at startup, runs each test with stdin closed, prints a blank-line-separated and underlined `TEST nn name` heading, then leaves numbered workspaces such as `test_09_update_command/` for inspection. It ends with a summary table that reports each test's status and execution time plus executed, passed, failed, and skipped totals. Test Git commands override line-ending config so local `core.autocrlf` settings do not add CRLF warnings.

Current tests cover initialization, empty-folder startup, copied-manifest startup, adding modules, clone modes, stack root discovery, verify, status and available porcelain output, available remote checks, start/refresh/upload/finalize/sync, stack log, nested stacks, update modes and negatives, foreach commands, Git-style invocation, optional BusyBox `sh` compatibility, hooks, branch cleanup, graceful failures, and version output.

## Unsupported Repo Features

`git-stack` is not a full Android `repo` replacement. Version `0.4.1` does not support Gerrit integration, automatic PR creation, Android XML manifests, `copyfile`, `linkfile`, manifest include/layering features, Android `.repo/` storage layout, mirror management, module filters, shell completion, or full command parity with Android `repo`.

## Historical Reference

The historical implementation reference was an earlier submodule script, mainly for wrapper structure and shell portability patterns. It is not the current behavior specification.

## License

Copyright (C) 2026 fsteff.

`git-stack` is released under the GNU Affero General Public License, version 3 or later (`AGPL-3.0-or-later`).
