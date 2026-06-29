# git-stack

Version 0.4.1<br>
**Copyright (C) 2026 Flemming Steffensen**<br>
License: GNU Affero General Public License v3.0 or later<br>
SPDX-License-Identifier: AGPL-3.0-or-later<br>

`git-stack` is a small multi-repository workspace tool for managing many individual Git repositories as a single cohesive project. It is designed for modularized codebases where different parts of a project are kept in separate repositories.

Inspired by Android [`repo`](https://source.android.com/docs/setup/reference/repo), git-stack focuses on the features most useful with ordinary Git hosting and can support pull-request-based workflows out of the box. It is intended as a practical improvement over manually coordinating multiple repositories, while avoiding the complexity and common workflow problems associated with Git submodules, Git subtree, and Git subrepos.

A stack root repository contains a manifest with references to the repositories in the stack. This allows setup files, glue code, scripts, and documentation to live in the root repository, while `git-stack` checks out the referenced stack modules at their recorded paths and revisions. Nested stacks are supported as well, allowing one stack module to contain its own manifest and child modules.

Documentation map:

- This `README.md` is the user manual. It explains the motivation, requirements, installation, workspace layout, commands, examples, CI usage, and comparisons with submodules, subtrees, and git-subrepo.
- [`docs/implementation-summary.md`](docs/implementation-summary.md) is the concise implementation reference. It records the current behavior contract, manifest fields, command guarantees, error handling, and test coverage.

## Shared Source Without Repository Drama

`git-stack` is for projects that share source code across several normal Git repositories without turning that shared source into opaque packages or copying it into every consumer. It is a low-friction, developer-administered method: an outer repository records the project shape, and stack modules remain editable Git repositories with their own branches, remotes, history, and reviews.

The mental model is close to package references, but with source code. A project pins the version of each shared component in `.stack`; `git-stack sync` materializes those modules; `git-stack available` checks whether upstream module branches have moved; `git-stack update` changes a selected module version when you want that movement. Unlike a binary package reference, the checked-out module is still source that can be edited, tested, committed, and reviewed in its own repository.

This keeps project administration visible. Toolchain files, build glue, product documentation, and the manifest live in the outer repository. Reusable source lives in stack modules. A branch can contain both code changes and the manifest update that records the intended combined workspace state.

Ticket-style branch names such as `XX-123-short-description` are optional, but git-stack can use them to automate stack ids and conservative finalize lookups. It does not require a particular merge strategy; explicit finalization works with merge commits, rebase merges, squash merges, tags, or pinned revisions.

`git-stack` does not create pull requests itself. It prepares consistent branches and manifest state, then optionally allows tools such as Azure CLI, GitHub CLI, GitLab CLI, or repository scripts create PRs explicitly.

## Alternatives And Tradeoffs

### Monorepo
A [monorepo](https://en.wikipedia.org/wiki/Monorepo) is often the simplest answer when one organization owns the code, build, permissions, and release cadence. The friction starts when shared components need independent ownership, independent history, different access rules, or reuse by projects that should not inherit the whole repository.

`git-stack` keeps those components in separate repositories while giving developers one materialized workspace and one project-level manifest.

### Git Submodules

[Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) are built into Git and are good for pinning external repositories. Their common pain is workflow overhead: contributors need submodule-specific commands, parent reviews often show only a gitlink pointer change, and cross-repository work is easy to split incorrectly between the submodule and the parent.

`git-stack` makes the manifest a normal text file, keeps module paths ignored by the outer repository, and provides explicit commands for syncing, publishing module work, finalizing landed changes, and checking available upstream movement.

### Git Subtree

[Subtree](https://github.com/git/git/blob/master/contrib/subtree/git-subtree.txt) is useful when vendored source should become part of one repository's history and review flow. The tradeoff is that ownership boundaries blur: copied source lives in the consumer repository, history grows there, and upstream contribution requires subtree discipline.

`git-stack` does not vendor module source into the outer repository. Stack modules stay as standalone repositories, and the outer repository records which module revisions belong to the project.

### git-subrepo

[`Subrepo`](https://github.com/ingydotnet/git-subrepo) improves the copied-source model by adding commands and metadata for pulling from and pushing back to an upstream repository. It is a good fit when the consumer repository should contain the source directly, but still needs a path back upstream.

`git-stack` chooses a different model: source is not copied into the outer repository at all. Developers work in real nested repositories, and the manifest records the combined project state.

### Android repo

Android [`repo`](https://source.android.com/docs/setup/reference/repo) is powerful and proven for AOSP-scale workspaces. It is also tailored to Android's ecosystem, XML manifests, and Gerrit-centered workflows.

`git-stack` borrows the useful workspace idea but keeps the shape narrower: plain Git remotes, a readable `.stack` manifest, and commands that fit pull-request-based or script-driven project administration.

## Comparison

| Topic | Monorepo | Submodules | Subtree / subrepo | git-stack |
| --- | --- | --- | --- | --- |
| Best fit | One shared ownership boundary | Source in pinned external repositories | Vendored source in one repository | Easy sehared source across many normal repositories |
| Source location | One repository | Nested repository checkout | Copied into consumer history | Nested stack module repository |
| Project state | Repository commit | Gitlink plus `.gitmodules` | Consumer commits plus metadata | Text entries in `.stack` |
| Get workspace | Clone once | Clone plus submodule init/update | Clone once | Clone outer repo, then `git-stack sync` |
| Check upstream movement | Normal Git history | Submodule commands/manual checks | Pull/sync helper commands | `git-stack available` |
| Inspect combined history | Normal Git log | Per-repository logs | Consumer repository log | `git-stack log` |
| Publish shared changes | Push same repository | Push module, update then push parent  | Push consumer; optionally push upstream | `git-stack upload --finalize`<br>`git-stack upload`, PR, `git-stack finalize` |
| Main admin cost | Repository scale and access control | Submodule workflow knowledge | Vendored history discipline | Small tool and explicit manifest workflow |

## Requirements

This section is intentionally short until the project has its own public GitHub or Codeberg repository with installation packages or release artifacts.


- Git.
- A POSIX-like shell for `bin/git-stack`; Git Bash, or even bysybox is sufficient on Windows.
- Read access to every module repository listed in `.stack`.
- Write access to module repositories only when using `upload`.
- `git-stack` available on `PATH`, or invoked directly from the checkout.

Credential handling is delegated to Git. Does not store provider tokens in `.stack`.

## Installation And Invocation

Put `bin/` on `PATH` so the executable name `git-stack` is discoverable:

```sh
export PATH="$PWD/bin:$PATH"
```

Because the executable follows Git's external-command naming pattern, both forms work when `bin/` is on `PATH`:

```sh
git-stack status
git stack status
git stack help
```

Use `git-stack --help` for direct help output. Git may intercept `git stack --help` for its own manpage lookup before invoking external commands.

On Windows, `bin/git-stack.bat` locates Git Bash and forwards to the shell implementation. It first looks for `git-stack` next to the `.bat` file, then searches `PATH`. When executed by `sh` or Bash on Linux, macOS, or Git Bash, the same `.bat` file falls through to its shell fallback and executes the adjacent `git-stack` script.

Most commands may be run from the stack root, a normal subdirectory, or deep inside a checked-out stack module. `git-stack` walks upward to find `.stack`, then runs from that stack root.

You can also run directly from a checkout:

```sh
sh bin/git-stack --help
sh bin/git-stack version
```

## Workspace Model

A workspace has:

- an outer Git repository
- `.stack` tracked by the outer repository
- optional `.stack-rc` for local git-stack configuration; `rc` is used in the usual "run/configuration commands" sense
- `.gitignore` entries that ignore stack module contents
- one nested Git repository per stack module

Terminology:

- **stack root**: the workspace directory that contains `.stack`; all module paths are relative to this directory.
- **outer repository**: the Git repository at the stack root. It owns `.stack`, `.gitignore`, toolchain project files, local glue code, and documentation. `.stack-rc` is local optional configuration.
- **stack module**: a nested Git repository managed by git-stack.
- **module repository**: the remote/source repository behind a stack module.
- **module path**: the checkout path recorded in `.stack`, relative to the stack root.

The outer repository tracks coordination files and local workspace files. Source that is shared with other projects usually remains in stack modules.

Example stack project:

```text
acme-robot-stack/                         # outer repository
  .stack                                  # tracked manifest for all stack modules
  .stack-rc                               # optional local machine configuration
  .gitignore                              # ignores checked-out stack module contents
  README.md                               # outer workspace documentation

  products/
    rover-control/                        # stack module: application repository
      src/
      tests/

  firmware/
    boards/
      motor-controller/                   # stack module: board firmware repository
        src/
        include/

  shared/
    protocol/                             # stack module: shared protocol repository
      schema/
      generators/

  tools/
    release/
      ci-scripts/                         # stack module: build/release tooling repository
        pipelines/
        scripts/

  third_party/
    compression/
      zlib/                               # stack module: external dependency, often partial-cloned
        CMakeLists.txt
```

Each stack module directory is its own Git repository with its own `.git`, branches, commits, remotes, and review flow. Module paths in `.stack` are always relative to the stack root, even when commands are run from deep inside a stack module.

### Nested Stacks

A stack module may itself contain a `.stack` file. In that case it is a nested stack.

By default, `git-stack` uses the nearest `.stack` found by walking upward from the current directory. If you run a command inside a nested stack, that command operates on the nested stack. If you run from the parent stack root, the command operates on the parent stack.

Read-only and restore commands that can safely include nested stacks support `--recursive`:

```sh
git-stack status --recursive --porcelain
git-stack available --recursive --porcelain
git-stack verify --recursive
git-stack sync --recursive
git-stack log --recursive
```

Without `--recursive`, these commands print a `Notice:` when they discover nested stacks so you can choose whether to include them.

The matching manifest entries would use the same relative paths:

```ini
[module "products/rover-control"]
repo=https://example.invalid/acme/rover-control.git
target_branch=main

[module "firmware/boards/motor-controller"]
repo=https://example.invalid/acme/motor-controller.git
target_branch=main

[module "shared/protocol"]
repo=https://example.invalid/acme/protocol.git
target_branch=main

[module "tools/release/ci-scripts"]
repo=https://example.invalid/acme/ci-scripts.git
target_branch=main

[module "third_party/compression/zlib"]
repo=https://example.invalid/mirror/zlib.git
clone=partial
target_branch=main
```

Embedded toolchain workspace:

```text
motor-drive-workspace/                         # outer repository
  .stack
  .stack-rc
  .gitignore
  README.md

  e2studio/
    motor_drive_app/                           # E2Studio project files owned by outer repo
      .project
      .cproject

  ccs/
    motor_drive_app/                           # CCS project files owned by outer repo
      .project
      .cproject

  talia/
    motor_drive_app/                           # Talia project files owned by outer repo
      motor_drive_app.talia

  glue/
    board_startup/                             # local startup and toolchain glue
      startup.c
      linker_sections.ld

  config/
    pinmux/                                    # local board configuration
      motor_drive_pins.yaml

  src/
    shared/
      platform/
        hal/                                   # stack module: hardware abstraction layer
      comms/
        canopen/                               # stack module: CANopen stack
      motor/
        control/                               # stack module: motor-control algorithms

  projects/
    static_libs/
      math/
        fixed_point/                           # stack module used by static-library projects
      drivers/
        sensors/                               # stack module used by static-library projects
```

In this layout, the outer repository owns the toolchain-specific project files and any project glue needed to make E2Studio, CCS, and Talia consume the same source tree. The shared source code is inserted as stack modules at the paths expected by those project files. A static-library project may include source from several stack modules, such as `fixed_point` and `sensors`.

The matching manifest entries are still ordinary `[module "..."]` sections:

```ini
[module "src/shared/platform/hal"]
repo=https://example.invalid/embedded/hal.git
target_branch=main

[module "src/shared/comms/canopen"]
repo=https://example.invalid/embedded/canopen.git
clone=partial
target_branch=main

[module "src/shared/motor/control"]
repo=https://example.invalid/embedded/motor-control.git
target_branch=main

[module "projects/static_libs/math/fixed_point"]
repo=https://example.invalid/embedded/fixed-point.git
target_branch=main

[module "projects/static_libs/drivers/sensors"]
repo=https://example.invalid/embedded/sensor-drivers.git
target_branch=main
```

## Manifest States

Pending stack modules represent work that has been pushed for review:

```ini
[module "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
pending_branch=XX-123-short-description
base_revision=abc123
pushed_commit=def456
```

Finalized stack modules point to integrated commits:

```ini
[module "libs/foo"]
repo=https://example.invalid/foo.git
revision=def456
```

A finalized stack module may also record a tag:

```ini
tag=v1.2.3
revision=def456
```

## Typical Workflow

```sh
git-stack init
git-stack add https://example.invalid/foo.git libs/foo
git-stack available
git-stack start XX-123-short-description --stash-dirty

# edit and commit inside libs/foo
git-stack upload

# optional explicit PR creation through provider tools or scripts
git-stack foreach-modified -- scripts/create-module-pr.sh
scripts/create-outer-pr.sh

# after module PRs land
git-stack finalize libs/foo --revision <merged-sha>
git-stack check
git-stack sync
```

For projects that do not need a separate module PR step, upload and pin the pushed module commits directly:

```sh
git-stack upload --finalize
git-stack check
git-stack sync
```

## CI And Build Servers

Most CI systems should check out the outer repository normally, then hand over to git-stack to materialize the stack modules:

```sh
git-stack sync
git-stack verify
```

The runner needs Git, git-stack, and credentials that can read every module repository. If the build only needs exact checked-out versions, force lightweight clones on the build machine with `.stack-rc`:

```ini
[clone]
mode=partial
```

Use `mode=full` on backup or archive machines that should fetch complete module repositories. Use `mode=manifest` when CI should honor each stack module's `clone=` setting from `.stack`.

For locked-down build hosts that should not have Git or repository secrets, split the pipeline into two jobs:

1. Source assembly job:
   - runs on a runner with Git, git-stack, and repository credentials;
   - checks out the outer repository;
   - runs `git-stack sync`;
   - runs `git-stack verify`;
   - publishes the complete workspace as a pipeline artifact.
2. Build job:
   - downloads the assembled workspace artifact;
   - runs only the compiler/toolchain;
   - does not need Git, git-stack, or repository credentials.

This generic pattern works with Azure DevOps, GitHub Actions, GitLab CI, Gitea, Jenkins, TeamCity, Bamboo, and similar systems. Provider-specific extensions are intentionally not required for v0.4; pipeline examples should be thin wrappers around `git-stack sync` and `git-stack verify`.

## Commands

### `git-stack init [--rc]`

Initializes the stack root. It creates `.stack` and `.gitignore` if needed. If the current directory is not already a Git repository, it runs `git init`.

`git-stack` uses built-in defaults when `.stack-rc` is absent. Use `--rc` when you want to create the default local configuration file for editing:

```sh
git-stack init --rc
```

Example:

```sh
mkdir workspace
cd workspace
git-stack init
```

Example output:

```text
Initialized git-stack workspace.
```

### `git-stack add [--clone <full|partial>] <repo> <path>`

Clones a module repository into `<path>`, adds `<path>/` to the outer `.gitignore`, and records the stack module in `.stack`.

Example:

```sh
git-stack add https://example.invalid/foo.git libs/foo
git-stack add --clone partial https://example.invalid/zlib.git third_party/zlib
```

Example output:

```text
Added module libs/foo.
```

`--clone partial` records `clone=partial` and uses `git clone --filter=blob:none`. This is useful for large third-party repositories where the workspace usually needs only the checked-out version. Omit `--clone` for the default full clone.

### `git-stack status [--recursive] [--porcelain]`

Prints the outer branch, stack metadata, stack module state, missing stack module checkouts, and dirty stack module markers.

Example:

```sh
git-stack status
```

Example output:

```text
outer branch: XX-123-work
stack id: XX-123
stack branch: XX-123-work
modules:
  libs/foo: pending XX-123-work
  libs/bar: finalized a1b2c3d4e5f6
```

If a checked-out stack module is itself a stack root, non-recursive status prints a `Notice:` suggesting `--recursive`. Use `git-stack status --recursive` to include nested stacks.

Use `--porcelain` for scripts:

```sh
git-stack status --recursive --porcelain
```

Porcelain output is tab-separated. Dirty repositories print their path and the underlying `git status --porcelain` line. Missing stack module checkouts print `!! missing`.

```text
.\t M README.md
libs/foo\t?? scratch.txt
libs/missing\t!! missing
```

The command exits `0` when status collection succeeds, even when output is non-empty. For clean-state checks, treat non-empty output as dirty or incomplete.

### `git-stack available [--recursive] [--porcelain]`

Checks module remotes for newer target-branch commits without fetching, checking out files, or rewriting `.stack`. It uses `git ls-remote`, so it contacts remotes but does not update local remote-tracking refs.

Use this when you want to know whether shared source has moved forward in its origin repository before deciding to update.

Example:

```sh
git-stack available
```

Example output:

```text
modules:
  libs/hal: up to date main abc1234
  libs/protocol: available main abc1234 -> def5678
  libs/foo: pending XX-123-work
  libs/missing: missing checkout; remote main def5678
```

Related commands:

- `git-stack sync` materializes the recorded manifest state.
- `git-stack update <module> --remote` changes one module to the remote target head and rewrites `.stack`.
- `git-stack log` shows local stack history and does not contact remotes.

Use `--porcelain` when automation needs stable records:

```sh
git-stack available --recursive --porcelain
```

Porcelain output omits up-to-date and pending modules. Non-empty output means there are available updates, missing checkouts, or remote availability problems.

```text
libs/protocol\tavailable\tmain\tabc123...\tdef567...
libs/missing\tmissing\tmain\tdef567...
libs/bad\terror\tremote-branch-missing\tmain
```

Remote/query failures still return nonzero.

If a checked-out stack module is itself a stack root, use `git-stack available --recursive` to include nested stacks.

### `git-stack verify [--recursive]`

Checks that the checkout matches `.stack` and `.stack-rc` without modifying files. It validates stack module existence, remotes, pinned revisions or tags, branch resolvability, and effective clone mode. Dirty stack modules are warnings; structural mismatches return a nonzero exit.

Example:

```sh
git-stack verify
```

Example output:

```text
Stack verified.
```

If nested stacks are present, use `git-stack verify --recursive` to verify them in the same run.

### `git-stack start <ticket-and-slug|.> [options]`

Creates or checks out the same branch in the outer repository and all checked-out stack modules. Stack module branches created by `start` are candidates only: they do not become pending in the manifest until committed work is uploaded. `start` also records the stack branch and ticket id in the manifest.

If the current folder is not a Git repository, `start <branch>` initializes it, creates `.stack`, creates the branch, and records the stack metadata. Existing files are allowed. If the folder contains subdirectories, interactive runs ask for confirmation and non-interactive runs require `--sure`.

Before switching branches, `start` scans the outer repository and checked-out stack modules. If any repository has dirty or untracked files, it lists them and asks what to do. Non-interactive scripts can use `--stash-dirty`, `--discard-dirty`, or `--cancel-dirty`. `--discard-dirty` resets tracked edits only and fails if untracked files remain.

Use `git-stack start .` to refresh the current branch layout without creating or switching branches. Add trailing `--hooks` to install managed hooks after the start action.

Example:

```sh
git-stack start XX-123-short-description
git-stack start XX-123-short-description --sure
git-stack start . --hooks
```

Example output:

```text
Started stack branch XX-123-short-description.
```

### `git-stack refresh`

Refreshes local manifest state without pushing. It records the current outer branch and records pending metadata for clean stack modules with committed work ahead of their target branch. Dirty stack modules are skipped with a warning.

Example:

```sh
git-stack refresh
git-stack refresh --quiet
```

Example output:

```text
Refreshed current git-stack state.
```

### `git-stack upload [--finalize]`

Pushes committed work for affected stack modules and pushes the outer repository branch. By default, each affected stack module is recorded as pending with `target_branch`, `pending_branch`, `base_revision`, and `pushed_commit`.

An affected stack module is a checked-out stack module with commits ahead of its target branch. Unchanged candidate branches created by `start` are skipped. If any checked-out stack module has uncommitted changes, `upload` fails and asks you to commit or stash first.

Each stack module uses its actual current branch as `pending_branch`. The stack module branch does not need to match the outer stack branch.

`upload` does not create pull requests. Run provider tools or repository scripts afterward if your workflow creates PRs immediately after pushing branches.

Use `--finalize` when pushed module commits should be pinned immediately without a pending review step. This is equivalent to uploading and then immediately finalizing each changed module with the pushed commit SHA, but it writes finalized state directly:

```ini
revision=<pushed-sha>
finalized_from_branch=<module-branch>
```

`finalized_from_branch` is a local cleanup hint for `git-stack cleanup-branches`; remote branches are not deleted.

Example:

```sh
git-stack upload
git-stack upload --finalize
```

Example output:

```text
Uploaded module libs/foo branch foo/XX-123 at a1b2c3d4e5f6.
Uploaded and finalized module libs/bar branch bar/XX-124 at b2c3d4e5f6a7.
Warning: outer repository has no origin remote; skipped outer push
```

Example with stack module-specific branch names:

```sh
git-stack start XX-123-stack
git -C libs/foo checkout -b foo/XX-123
# commit work in libs/foo
git-stack upload
# manifest records pending_branch=foo/XX-123 for libs/foo
```

### `git-stack foreach -- <command> [args...]`

Runs a command in every checked-out stack module listed in `.stack`. The command is executed directly from each stack module directory.

Example:

```sh
git-stack foreach -- git status --short
```

Example output:

```text
== libs/foo ==
 M src/foo.c
== libs/bar ==
```

Use `sh -c` for shell features:

```sh
git-stack foreach -- sh -c 'printf "%s %s\n" "$GIT_STACK_MODULE_PATH" "$(git branch --show-current)"'
```

### `git-stack foreach-modified -- <command> [args...]`

Runs a command only in pending stack modules, where pending means the manifest section contains `pending_branch=...`. This is designed for explicit post-upload tasks such as PR creation.

Example with literal arguments:

```sh
git-stack foreach-modified -- git branch --show-current
```

Example output:

```text
== libs/foo ==
foo/XX-123
```

For provider commands that need shell variable expansion, use:

```sh
git-stack foreach-modified -- sh -c 'az repos pr create --source-branch "$GIT_STACK_PENDING_BRANCH"'
```

A common pattern is to keep provider-specific automation in scripts owned by the outer repository:

```text
scripts/
  create-module-pr.sh
  create-outer-pr.sh
```

Then run:

```sh
git-stack upload
git-stack foreach-modified -- scripts/create-module-pr.sh
scripts/create-outer-pr.sh
```

Keep executable PR commands out of `.stack`. The manifest is shared coordination data; provider commands usually need local credentials, reviewers, labels, policies, and host-specific defaults. Store those choices in repository scripts, CI configuration, environment variables, or local `.stack-rc` settings instead.

### `git-stack check`

Reports pending stack modules and exits nonzero while any `pending_branch` remains in the manifest. Use this as a merge gate for the outer repository.

Example:

```sh
git-stack check
```

Example output when work is still pending:

```text
libs/foo: pending branch foo/XX-123
```

### `git-stack log [options]`

Shows a read-only combined history view across the active stack root and checked-out stack modules. It does not fetch, copy commits, merge histories, or rewrite history.

Default output shows the newest 50 commits across the active stack. Each line contains the commit time, repository label, short SHA, and subject.

Options:

- `--max-count <n>`: limit the combined output; default is `50`.
- `--since <date>` and `--until <date>`: filter each repository's log.
- `--module <path>`: show only `.` or one stack module.
- `--oneline`: compact output.
- `--recursive`: include nested stacks.

Example:

```sh
git-stack log --max-count 4
```

Example output:

```text
2030-01-03T09:30:00+00:00  libs/platform            a1b2c3d  HAL-210 Add watchdog reset hook
2030-01-03T08:10:00+00:00  .                        91e4abc  HAL-210 Update stack manifest
2030-01-02T16:42:00+00:00  libs/hal                 83df120  HAL-210 Fix CAN timeout
2030-01-02T14:15:00+00:00  drivers/sensors          d4e5f6a  Add temperature conversion
```

Compact example:

```sh
git-stack log --oneline --module libs/hal --max-count 2
```

Example output:

```text
libs/hal                 83df120 HAL-210 Fix CAN timeout
libs/hal                 4492bc0 Add CAN error counters
```

If nested stacks are discovered without `--recursive`, `log` prints a `Notice:` explaining that `--recursive` can include them.

### `git-stack update <module> [mode]`

Updates one clean, non-pending stack module to another recorded version and checks it out locally. Without a mode, `update` fetches and uses the module's `target_branch` head.

Modes:

- `--target-head`: fetch and pin the current `origin/<target_branch>` commit.
- `--remote`: alias for `--target-head`, matching the common Git submodule spelling.
- `--revision <sha-or-ref>`: pin an explicit commit or resolvable ref.
- `--tag <tag>`: pin a tag and record both `tag=` and its resolved `revision=`.

Options:

- `--branch <branch>` or `--set-branch <branch>`: change the module's `target_branch` before resolving the update. This can be combined with `--remote`, `--target-head`, or `--revision`, but not `--tag`.
- `--no-fetch`: resolve from local refs only. Use this when the build or script has already fetched exactly the refs it should use.

`update` refuses dirty stack modules and pending stack modules so review state is not overwritten.

Example:

```sh
git-stack update libs/foo
git-stack update libs/foo --remote
git-stack update libs/foo --branch release/1 --remote
git-stack update libs/foo --remote --no-fetch
git-stack update libs/foo --revision abc123
git-stack update libs/foo --tag v1.2.3
```

Example output:

```text
Updated libs/foo to a1b2c3d4e5f6.
```

### `git-stack finalize <module> [mode] [--cleanup]`

Converts a pending stack module into a finalized stack module. Exactly one explicit mode may be used:

```sh
git-stack finalize libs/foo --revision <sha>
git-stack finalize libs/foo --tag v1.2.3
git-stack finalize libs/foo --use-target-head
git-stack finalize libs/foo --revision <sha> --cleanup
```

Example output:

```text
Finalized libs/foo at a1b2c3d4e5f6.
```

Without a mode, `finalize` attempts conservative auto-resolution using the stack ticket key. It only accepts one unambiguous match.

`--cleanup` deletes the local pending branch after finalization. It never deletes remote branches or untracked files.

### `git-stack cleanup-branches`

Deletes local branches recorded as cleanup hints by finalized stack modules. This is idempotent and local-only.

Example:

```sh
git-stack cleanup-branches
```

Example output:

```text
Deleted local branch foo/XX-123 in libs/foo.
```

### `git-stack install-hooks` / `git-stack remove-hooks`

Installs or removes managed hooks in the outer repository and every checked-out stack module. Installed hooks run `git-stack refresh --quiet` from `post-checkout`, `post-commit`, and `pre-push` events. Hooks never push or create PRs.

When managed hooks are already installed in the outer repository, `git-stack add` installs the same managed hooks in the newly added module, and `git-stack sync` installs them in newly cloned missing modules. Nested stacks manage their own hook installation from their own stack roots.

Example:

```sh
git-stack install-hooks
git-stack remove-hooks
```

Example output:

```text
Installed hooks in .
Installed hooks in libs/foo.
```

### `git-stack sync [--recursive]`

Clones missing stack modules, fetches existing stack modules, and checks out each stack module's manifest state. Pending stack modules restore the pending branch where possible. Finalized stack modules check out the pinned revision or tag. If one stack module fails, `sync` continues with the remaining stack modules, then exits nonzero with a summary of failed module paths.

`sync` applies clone mode only when a stack module directory is missing. Changing a manifest entry from `clone=full` to `clone=partial` does not convert an existing checkout; remove that stack module directory and run `git-stack sync` to recreate it.

Example:

```sh
git-stack sync
```

For nested stacks:

```sh
git-stack sync --recursive
```

Example output:

```text
Syncing stack: .
Synced firmware.
Syncing stack: firmware
Synced drivers/io.
Syncing stack: firmware/drivers/io
Synced chips/adc.
```

Minimal copied-manifest startup:

```sh
mkdir workspace
cp path/to/.stack workspace/.stack
cd workspace
git-stack sync
```

## Clone Modes

Each stack module may opt into lightweight partial clone:

```ini
[module "third_party/zlib"]
repo=https://example.invalid/zlib.git
clone=partial
target_branch=main
revision=abc123
```

Missing `clone=` means `full`. Partial clone uses Git's `--filter=blob:none`; it is not a shallow clone, so history and other versions can still be fetched later.

`.stack-rc` can override clone behavior for a machine:

```ini
[clone]
mode=manifest
```

Use `mode=full` to force complete clones, for example on a backup machine. Use `mode=partial` to force lightweight clones, for example on a build server. `mode=manifest` uses each stack module's own `clone=` setting.

### `git-stack version`

Prints the installed version.

Example:

```sh
git-stack version
```

Example output:

```text
git-stack 0.4.1
```

`git-stack --version` is also supported.

## Foreach Environment

`foreach` and `foreach-modified` expose stack module context through environment variables:

- `GIT_STACK_ROOT`: stack root
- `GIT_STACK_MODULE_PATH`: manifest module path
- `GIT_STACK_MODULE_ABSPATH`: absolute module path
- `GIT_STACK_MODULE_REPO`: configured module repository URL
- `GIT_STACK_BRANCH`: current module branch
- `GIT_STACK_TARGET_BRANCH`: target branch from the manifest
- `GIT_STACK_PENDING_BRANCH`: pending branch, when present
- `GIT_STACK_BASE_REVISION`: recorded base revision, when present
- `GIT_STACK_PUSHED_COMMIT`: recorded pushed commit, when present
- `GIT_STACK_REVISION`: finalized revision, when present
- `GIT_STACK_TAG`: finalized tag, when present
- `REPO_PATH` and `REPO_PROJECT`: compatibility aliases for the module path

Missing stack modules are skipped with a warning. If a command fails in a stack module, iteration stops and `git-stack` returns that exit code.

Quotes are not needed for simple commands:

```sh
git-stack foreach -- git status --short
```

Use a shell and quotes only when you need shell syntax such as variable expansion, redirection, pipes, or command substitution:

```sh
git-stack foreach -- sh -c 'printf "%s %s\n" "$GIT_STACK_MODULE_PATH" "$(git branch --show-current)"'
```

## Git Hooks

Hooks are opt-in through `git-stack install-hooks` or `git-stack start <branch|.> --hooks`. Managed hooks update local manifest state by running `git-stack refresh --quiet`. Installation is all-or-nothing: `git-stack` refuses to overwrite unmanaged hooks before writing any managed hook.

Hooks should not call `git-stack upload` automatically. Upload pushes branches and records review intent, which would be surprising if triggered implicitly by another Git client.

## Tests

The integration tests are POSIX shell scripts that create local Git repositories under a persistent test root. By default this is `${TMPDIR:-/tmp}/git-stack-test-workspaces` so startup tests are not affected by the tool repository's own Git root. Set `TEST_ROOT` to override it.

On Linux and macOS, run the full suite with:

```sh
sh tests/run-all.sh
```

If you prefer executing scripts directly, first ensure executable permissions are set:

```sh
chmod +x bin/git-stack tests/run-all.sh tests/*.sh
tests/run-all.sh
```

From `cmd.exe` on Windows, run the polyglot batch wrapper:

```bat
tests\run-all.bat
```

The runner clears the test root at startup, recreates local repositories for each test, and leaves them in numbered folders such as `test_01_auto_finalize/` for inspection. Each test heading is preceded by a blank line and underlined, and the run ends with a table showing every test, status, execution time, and totals for executed, passed, failed, and skipped tests. The suite runs tests with stdin closed so interactive prompts cannot affect automated results. Test Git commands override line-ending config to avoid local `core.autocrlf` noise. The suite also puts `bin/` on `PATH` so tests verify both direct `git-stack` usage and Git external-command invocation through `git stack`.

The suite includes an optional BusyBox compatibility test. It runs automatically when `C:\busybox\bin\busybox.exe` exists, or when `BUSYBOX_EXE` points to a BusyBox executable. If BusyBox is not available, that test prints `SKIP` and the rest of the suite continues.

## AI User Skill

The repository includes `skills/git-stack/` for AI agents working in projects that use `git-stack`. This is the skill to copy into consuming projects. It teaches agents how to inspect, sync, verify, edit, and prepare work in a stack workspace, with explicit rules not to modify the `git-stack` tool itself.

Active maintainer instructions for this repository live in `AGENTS.md`. The repo-local `skills/` directory is not an active agent configuration; it is source material that can be copied into projects that consume `git-stack`.

For projects that consume `git-stack`, copy the runtime scripts plus the user skill:

```text
bin/git-stack
bin/git-stack.bat
bin/git_stack.sh
skills/git-stack/
```

The repo-local `skills/` directory is a distributable source location. To make the skill active, copy the entire `skills/git-stack/` folder to a Codex skill location so the destination folder contains `SKILL.md` directly.

### Windows Codex Skill Locations

For a personal Windows install, use the Codex user skill location used by your Codex setup. Common locations are:

```text
C:\Users\<you>\.codex\skills\git-stack\
%CODEX_HOME%\skills\git-stack\
```

`%CODEX_HOME%` overrides the default Codex home when it is set. Restart Codex after adding or changing installed skills if the skill does not appear immediately.

Codex also supports repo-scoped skill folders in `.agents\skills\` while walking from the current working directory up to the repository root. This is useful when a consuming project wants to check in a skill that applies only to that project or one subtree:

```text
<repo>\.agents\skills\git-stack\
```

Some Codex installations or plugins may also use project-local `.codex\` folders for configuration or installed assets. Verify the active Codex version before relying on `.codex\skills\` as a checked-in distribution path.

You can invoke the skill explicitly with `$git-stack`, or use `/skills` or the Codex skill UI where available. `$skill-installer` is useful for curated or GitHub-hosted skills; for this repository, copying `skills\git-stack\` is enough because the skill is already present in the checkout.

Maintainers changing `git-stack` itself should read `docs/maintainer.md` and use `docs/implementation-summary.md` as the behavior contract.

## License

Copyright (C) 2026 fsteff.

`git-stack` is released under the GNU Affero General Public License, version 3 or later (`AGPL-3.0-or-later`).
