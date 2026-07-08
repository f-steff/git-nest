---
name: git-nest
description: Use git-nest in an application or firmware workspace that consumes the tool. Use when an AI agent needs to inspect, sync, verify, edit, test, or prepare changes in a project with a .gitnest manifest and nested subprojects, while avoiding modifications to the git-nest tool itself.
---

# git-nest

Use this skill when working in a project that already uses `git-nest`. The goal is to work safely in the consuming project, not to maintain `git-nest` itself.

## Hard Rules

- Do not modify `bin/git-nest`, `bin/git-nest.bat`, or `bin/git_nest.sh` unless the user explicitly asks to change the tool.
- Treat `.gitnest` as project coordination state. Prefer `git-nest` commands over manual edits.
- Do not run `git-nest upload`, push branches, install hooks, or finalize subprojects unless the user explicitly asks.
- Do not delete subprojects or rewrite branches to clean up unless the user explicitly asks.
- Preserve each repository boundary. A project root commit and subproject commits are separate Git histories.

## Discovery

From anywhere inside a project workspace, start with:

```sh
git nest version
git nest status
git nest outdated
git nest verify
git nest doctor --offline
git nest log --max-count 10
```

If `git nest` is not available, try:

```sh
git-nest version
sh bin/git-nest version
bin/git-nest.bat version
```

Use the command form already used by the project when possible.

## Normal Workflow

Before editing:

```sh
git nest sync
git nest status
git nest outdated
git nest verify
```

Use `sync` to fetch and restore subprojects recorded in `.gitnest`. Use `status` to understand project root and subproject state. Use `verify` to catch missing subprojects, wrong remotes, unresolved refs, or checkout drift.

Use `doctor --offline` as a local sanity check before longer investigations or test runs. Use plain `doctor` when remote reachability is part of the question.

Use `outdated` when the user wants to know whether subproject remotes have newer target-branch commits without updating `.gitnest`, fetching local refs, or changing checkouts.

Use `log` as a read-only project history view. It shows recent commits across the project root and checked-out subprojects without fetching or rewriting history.

When changing code:

- Edit files in the repository that owns them.
- Shared source inside a subproject belongs to that subproject repository.
- Project glue, IDE project files, build scripts, and `.gitnest` usually belong to the project root repository.
- Run project tests/builds from the project root unless the project documents a different workflow.

After editing, inspect both project root and subproject state:

```sh
git nest status
git status --short
git nest foreach -- git status --short
git nest foreach-modified --porcelain
git nest log --max-count 10
```

## Nested Projects

A subproject may itself contain a `.gitnest` file. By default, `git-nest` uses the nearest `.gitnest` found by walking upward from the current directory. If a command prints `Notice: nested project found ...`, rerun with `--recursive` only when the user wants nested project state included:

```sh
git nest status --recursive
git nest outdated --recursive
git nest verify --recursive
git nest snapshot --recursive
```

Write-side commands preserve project boundaries. From a parent project, do not run path-changing commands against paths inside a nested project; run from the nested project root instead. Use `snapshot --recursive` only when the user wants recursive local manifest refresh. `no-pending` is scoped to the current project, so run it from each nested project that has its own merge gate. Keep current-project scoped commands such as `diff`, `foreach-*`, and `export` rooted where the user asked you to run them.

Use porcelain output when a script or automation step needs stable records:

```sh
git nest status --recursive --porcelain
git nest outdated --recursive --porcelain
```

For `status --porcelain`, non-empty output means the project workspace is dirty or incomplete. For `outdated --porcelain`, non-empty output means newer subproject commits, missing checkouts, or remote query problems were found.

Use filtered foreach commands when you need to inspect or operate on a subset of checked-out subprojects:

```sh
git nest foreach-modified --porcelain
git nest foreach-clean --porcelain
git nest foreach-modified -- sh -c 'git status --short'
```

`foreach-modified` means dirty working trees. `foreach-clean` means clean checked-out subprojects. `foreach-pending` means manifest entries with `pending_branch=...`; use it for review or PR workflows after `upload`.

## Branching

Only start coordinated branches when the user asks:

```sh
git nest start XX-123-short-description
```

Use `git nest start .` when the user wants `git-nest` to record current branches without creating or switching branches.

If dirty files exist, ask before choosing `--stash-dirty`, `--discard-dirty`, or cancellation. Do not discard work automatically.

## Preparing Review State

Use this only when the user asks to prepare or publish work:

```sh
git nest snapshot
git nest snapshot --dry-run
git nest upload
git nest upload --dry-run
git nest upload --finalize
git nest no-pending
```

`snapshot` updates local manifest state without pushing. `snapshot --dry-run` prints manifest field changes without writing. `upload` pushes changed subproject branches and records pending subproject state in `.gitnest`. `upload --dry-run` prints planned pushes and manifest changes without pushing, fetching, or writing. `upload --finalize` pushes changed subproject branches and records the pushed commits directly as finalized revisions when the user does not want a separate review/finalize step. `no-pending` fails while pending subprojects remain.

`git-nest` does not create pull requests by itself. If the project uses provider tooling, create PRs only when the user asks, commonly after upload:

```sh
git nest foreach-pending -- az repos pr create ...
```

## Updating Project Subprojects

Only change subproject versions when the user asks. Prefer command-driven updates:

```sh
git nest update libs/foo --remote
git nest update libs/foo --revision <sha>
git nest update libs/foo --tag <tag>
git nest update libs/foo --branch release/1 --remote
```

Use `--no-fetch` only when the caller intentionally wants local refs without fetching.

After an update, inspect `.gitnest` and run:

```sh
git nest verify
```

## Changing Project Shape

Only change project shape when the user explicitly asks. Prefer command-driven changes:

```sh
git nest remove <path>
git nest remove <path> --keep-files
git nest mv <old-path> <new-path>
git nest mv --url <new-url> <path>
git nest extract <path> <remote-url>
git nest absorb <path>
```

`remove` deletes the checkout by default and removes the manifest entry. Use `--keep-files` when the user wants to stop managing the path without deleting the checkout. `mv` moves a managed subproject path and updates `.gitnest` and `.gitignore`; `mv --url` changes only the manifest URL and does not change the checkout remote.

`extract` turns tracked outer-repository files into a managed subproject and stages the outer manifest/ignore/file removals. `extract --force` only overrides staged outer-repository changes under the extracted path; it does not override dirty files, untracked files, or non-empty remotes. `absorb` turns a managed subproject back into outer-repository files and leaves the remote untouched. It has no force mode. Inspect `git nest status` and `git status --short` before and after.

## Exporting Snapshots

Only export source snapshots when the user asks, especially if the export may include dirty working-tree content:

```sh
git nest export --output build/source.tar.gz --deterministic
git nest export --output build/source-dir --format dir
```

`export` writes `.gitnest`, a generated `MANIFEST.lock`, and tracked subproject working-tree files. It omits ignored files and strips `.git` directories unless `--include-git` is passed. It refuses dirty subprojects unless the user explicitly asks for `--allow-dirty`.

## Finalizing Pending Subprojects

Only finalize when the user says a subproject change is approved or merged:

```sh
git nest finalize libs/foo --revision <sha>
git nest finalize libs/foo --tag v1.2.3
git nest finalize libs/foo --use-target-head
git nest finalize libs/foo --dry-run --use-target-head
git nest no-pending
```

Use explicit `--revision` or `--tag` when known. Avoid relying on auto-finalize if there is any ambiguity.

## IDE And Build Hooks

Some consuming projects call `bin/git-nest.bat` from IDE build or post-build steps because it is polyglot: `cmd.exe` executes the batch section, while `sh`/Bash executes the shell fallback. This lets one project configuration work across Windows, Linux, and macOS.

Do not remove or replace those calls casually. If a build hook fails, first verify the tool is outdated and the workspace is a valid project:

```sh
bin/git-nest.bat version
bin/git-nest.bat status
```

## When In Doubt

Prefer read-only commands first:

```sh
git nest status
git nest outdated
git nest verify
git nest doctor --offline
git nest foreach -- git status --short
```

Use `git nest sync --dry-run`, `snapshot --dry-run`, `upload --dry-run`, and `finalize --dry-run` to preview supported mutating flows. The README Recovery Cookbook has copy-paste recovery steps for common failures.

Ask before running commands that mutate repositories, push branches, install hooks, finalize subprojects, discard changes, or alter `.gitnest`.
