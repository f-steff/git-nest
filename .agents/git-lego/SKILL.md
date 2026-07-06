---
name: git-lego
description: Use git-lego in an application or firmware workspace that consumes the tool. Use when an AI agent needs to inspect, sync, verify, edit, test, or prepare changes in a project with a .gitlego manifest and nested subprojects, while avoiding modifications to the git-lego tool itself.
---

# git-lego

Use this skill when working in a project that already uses `git-lego`. The goal is to work safely in the consuming project, not to maintain `git-lego` itself.

## Hard Rules

- Do not modify `bin/git-lego`, `bin/git-lego.bat`, or `bin/git_lego.sh` unless the user explicitly asks to change the tool.
- Treat `.gitlego` as project coordination state. Prefer `git-lego` commands over manual edits.
- Do not run `git-lego upload`, push branches, install hooks, or finalize subprojects unless the user explicitly asks.
- Do not delete subprojects or rewrite branches to clean up unless the user explicitly asks.
- Preserve each repository boundary. A project root commit and subproject commits are separate Git histories.

## Discovery

From anywhere inside a project workspace, start with:

```sh
git lego version
git lego status
git lego outdated
git lego verify
git lego doctor --offline
git lego log --max-count 10
```

If `git lego` is not available, try:

```sh
git-lego version
sh bin/git-lego version
bin/git-lego.bat version
```

Use the command form already used by the project when possible.

## Normal Workflow

Before editing:

```sh
git lego sync
git lego status
git lego outdated
git lego verify
```

Use `sync` to fetch and restore subprojects recorded in `.gitlego`. Use `status` to understand project root and subproject state. Use `verify` to catch missing subprojects, wrong remotes, unresolved refs, or checkout drift.

Use `doctor --offline` as a local sanity check before longer investigations or test runs. Use plain `doctor` when remote reachability is part of the question.

Use `outdated` when the user wants to know whether subproject remotes have newer target-branch commits without updating `.gitlego`, fetching local refs, or changing checkouts.

Use `log` as a read-only project history view. It shows recent commits across the project root and checked-out subprojects without fetching or rewriting history.

When changing code:

- Edit files in the repository that owns them.
- Shared source inside a subproject belongs to that subproject repository.
- Project glue, IDE project files, build scripts, and `.gitlego` usually belong to the project root repository.
- Run project tests/builds from the project root unless the project documents a different workflow.

After editing, inspect both project root and subproject state:

```sh
git lego status
git status --short
git lego foreach -- git status --short
git lego foreach-modified --porcelain
git lego log --max-count 10
```

## Nested Projects

A subproject may itself contain a `.gitlego` file. By default, `git-lego` uses the nearest `.gitlego` found by walking upward from the current directory. If a command prints `Notice: nested project found ...`, rerun with `--recursive` only when the user wants nested project state included:

```sh
git lego status --recursive
git lego outdated --recursive
git lego verify --recursive
git lego snapshot --recursive
```

Write-side commands preserve project boundaries. From a parent project, do not run path-changing commands against paths inside a nested project; run from the nested project root instead. Use `snapshot --recursive` only when the user wants recursive local manifest refresh. `no-pending` is scoped to the current project, so run it from each nested project that has its own merge gate. Keep current-project scoped commands such as `diff`, `foreach-*`, and `export` rooted where the user asked you to run them.

Use porcelain output when a script or automation step needs stable records:

```sh
git lego status --recursive --porcelain
git lego outdated --recursive --porcelain
```

For `status --porcelain`, non-empty output means the project workspace is dirty or incomplete. For `outdated --porcelain`, non-empty output means newer subproject commits, missing checkouts, or remote query problems were found.

Use filtered foreach commands when you need to inspect or operate on a subset of checked-out subprojects:

```sh
git lego foreach-modified --porcelain
git lego foreach-clean --porcelain
git lego foreach-modified -- sh -c 'git status --short'
```

`foreach-modified` means dirty working trees. `foreach-clean` means clean checked-out subprojects. `foreach-pending` means manifest entries with `pending_branch=...`; use it for review or PR workflows after `upload`.

## Branching

Only start coordinated branches when the user asks:

```sh
git lego start XX-123-short-description
```

Use `git lego start .` when the user wants `git-lego` to record current branches without creating or switching branches.

If dirty files exist, ask before choosing `--stash-dirty`, `--discard-dirty`, or cancellation. Do not discard work automatically.

## Preparing Review State

Use this only when the user asks to prepare or publish work:

```sh
git lego snapshot
git lego snapshot --dry-run
git lego upload
git lego upload --dry-run
git lego upload --finalize
git lego no-pending
```

`snapshot` updates local manifest state without pushing. `snapshot --dry-run` prints manifest field changes without writing. `upload` pushes changed subproject branches and records pending subproject state in `.gitlego`. `upload --dry-run` prints planned pushes and manifest changes without pushing, fetching, or writing. `upload --finalize` pushes changed subproject branches and records the pushed commits directly as finalized revisions when the user does not want a separate review/finalize step. `no-pending` fails while pending subprojects remain.

`git-lego` does not create pull requests by itself. If the project uses provider tooling, create PRs only when the user asks, commonly after upload:

```sh
git lego foreach-pending -- az repos pr create ...
```

## Updating Project Subprojects

Only change subproject versions when the user asks. Prefer command-driven updates:

```sh
git lego update libs/foo --remote
git lego update libs/foo --revision <sha>
git lego update libs/foo --tag <tag>
git lego update libs/foo --branch release/1 --remote
```

Use `--no-fetch` only when the caller intentionally wants local refs without fetching.

After an update, inspect `.gitlego` and run:

```sh
git lego verify
```

## Changing Project Shape

Only change project shape when the user explicitly asks. Prefer command-driven changes:

```sh
git lego remove <path>
git lego remove <path> --keep-files
git lego mv <old-path> <new-path>
git lego mv --url <new-url> <path>
git lego extract <path> <remote-url>
git lego absorb <path>
```

`remove` deletes the checkout by default and removes the manifest entry. Use `--keep-files` when the user wants to stop managing the path without deleting the checkout. `mv` moves a managed subproject path and updates `.gitlego` and `.gitignore`; `mv --url` changes only the manifest URL and does not change the checkout remote.

`extract` turns tracked outer-repository files into a managed subproject and stages the outer manifest/ignore/file removals. `extract --force` only overrides staged outer-repository changes under the extracted path; it does not override dirty files, untracked files, or non-empty remotes. `absorb` turns a managed subproject back into outer-repository files and leaves the remote untouched. It has no force mode. Inspect `git lego status` and `git status --short` before and after.

## Exporting Snapshots

Only export source snapshots when the user asks, especially if the export may include dirty working-tree content:

```sh
git lego export --output build/source.tar.gz --deterministic
git lego export --output build/source-dir --format dir
```

`export` writes `.gitlego`, a generated `MANIFEST.lock`, and tracked subproject working-tree files. It omits ignored files and strips `.git` directories unless `--include-git` is passed. It refuses dirty subprojects unless the user explicitly asks for `--allow-dirty`.

## Finalizing Pending Subprojects

Only finalize when the user says a subproject change is approved or merged:

```sh
git lego finalize libs/foo --revision <sha>
git lego finalize libs/foo --tag v1.2.3
git lego finalize libs/foo --use-target-head
git lego finalize libs/foo --dry-run --use-target-head
git lego no-pending
```

Use explicit `--revision` or `--tag` when known. Avoid relying on auto-finalize if there is any ambiguity.

## IDE And Build Hooks

Some consuming projects call `bin/git-lego.bat` from IDE build or post-build steps because it is polyglot: `cmd.exe` executes the batch section, while `sh`/Bash executes the shell fallback. This lets one project configuration work across Windows, Linux, and macOS.

Do not remove or replace those calls casually. If a build hook fails, first verify the tool is outdated and the workspace is a valid project:

```sh
bin/git-lego.bat version
bin/git-lego.bat status
```

## When In Doubt

Prefer read-only commands first:

```sh
git lego status
git lego outdated
git lego verify
git lego doctor --offline
git lego foreach -- git status --short
```

Use `git lego sync --dry-run`, `snapshot --dry-run`, `upload --dry-run`, and `finalize --dry-run` to preview supported mutating flows. The README Recovery Cookbook has copy-paste recovery steps for common failures.

Ask before running commands that mutate repositories, push branches, install hooks, finalize subprojects, discard changes, or alter `.gitlego`.
