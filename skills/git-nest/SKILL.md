---
name: git-nest
description: Use git-nest in an application or firmware workspace that consumes the tool. Use when an AI agent needs to inspect, restore, verify, edit, test, or prepare changes in a project with a .gitnest manifest and nested subprojects, while avoiding modifications to the git-nest tool itself.
---

# git-nest

Use this skill when working in a project that already uses `git-nest`. The goal is to work safely in the consuming project, not to maintain `git-nest` itself.

## Hard Rules

- Do not modify `bin/git-nest`, `bin/git-nest.bat`, or `bin/git_nest.sh` unless the user explicitly asks to change the tool.
- Treat `.gitnest` as project coordination state. Prefer `git-nest` commands over manual edits.
- Do not push branches, install hooks, discard work, or alter `.gitnest` unless the user explicitly asks.
- Do not delete subprojects or rewrite branches to clean up unless the user explicitly asks.
- Preserve each repository boundary. A project root commit and subproject commits are separate Git histories.

## Discovery

From anywhere inside a project workspace, start with:

```sh
git nest version
git nest status
git nest list
git nest outdated
git nest verify
git nest doctor --offline
git nest log --max-count 10
```

Use `list` for a stable, scriptable inventory of managed subprojects (path, URL, target branch, revision, tag, checkout state, and reproducibility); it accepts `--porcelain` and `--json`/`--json-pretty`. Use `survey` to find nested repositories, submodules, or git-subrepos that are not managed by `.gitnest`; it is read-only and suggests a next step. `survey` labels a `detached` former subproject (a checkout left behind by `detach` whose path still carries a nest-owned ignore entry) and a `subrepo` (a `<path>/.gitrepo` marker):

```sh
git nest list --porcelain
git nest survey
```

Use `tree` for a quick visual overview grouped by shared path prefixes instead of `list`'s flat table; `--all` adds `survey`'s own unmanaged findings, and `--recursive` also descends into nested nests:

```sh
git nest tree
git nest tree --all --recursive
```

To bring everything `survey` finds into the nest in one step, use `absorb-all`; it never touches git-subrepos or subtrees (those need the explicit `absorb --subrepo`/`absorb --subtree` conversion) and rolls back the whole batch by default if one item fails partway through:

```sh
git nest absorb-all --dry-run
git nest absorb-all
```

git-nest keeps its ignore rules in a managed `# BEGIN git-nest ignores` block in `.gitignore`. If the user reports leftover ignore rules for directories they deleted, run `git nest repair`, which reconciles the block and prunes stale nest-owned entries; `git nest doctor` warns when stale entries exist. Do not hand-edit the managed block; edit via git-nest commands or `repair`.

If you find a `.gitnest-recovery-<op>-<name>-<timestamp>/` directory, a previous `inline` or `absorb --preserve-history` was interrupted. Open its `RECOVERY.txt` for exact restore and cleanup steps; `git nest doctor` also reports these leftovers. git-nest removes such backups automatically when a conversion succeeds, so one that remains means the earlier command did not finish.

If `git nest` is not available, try:

```sh
git-nest version
sh bin/git-nest version
bin/git-nest.bat version
```

Use the command form already used by the project when possible.

## Worktrees

If the project uses Git worktrees, each worktree maintains its own independent state:

- Each linked worktree has its own checkout of `.gitnest`, subproject checkouts, `.gitignore` managed block, and materialized state.
- Operations in one worktree (restore, snapshot, status, etc.) do not affect another worktree.
- The Git object store is shared, so cloning is efficient, but working trees are fully isolated otherwise.
- Treat each worktree as a separate workspace. If an agent is inside a linked worktree, all `git nest` commands operate on that worktree only.
- No special setup or configuration is needed -- git-nest is transparent to linked worktrees.

Example: after creating a linked worktree, run the usual discovery commands:

```sh
cd path/to/linked-worktree
git nest status
git nest restore
```

## Normal Workflow

Before editing:

```sh
git nest restore
git nest status
git nest outdated
git nest verify
```

Use `restore` to fetch and restore subprojects recorded in `.gitnest` for the current nest. Use `status` to understand nest root and subproject state. Use `verify` to catch missing subprojects, wrong remotes, unresolved refs, or checkout drift.

Use `doctor --offline` as a local sanity check before longer investigations or test runs. Use plain `doctor` when remote reachability is part of the question.

Use `outdated` when the user wants to know whether subproject remotes have newer target-branch commits without updating `.gitnest`, fetching local refs, or changing checkouts.

Use `log` as a read-only nest history view. It shows recent commits across the nest root and checked-out subprojects without fetching or rewriting history.

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

Write-side commands preserve nest boundaries. From a parent nest, do not run path-changing commands against paths inside a nested nest; run from the nested nest root instead. Use `snapshot --recursive` only when the user wants recursive local manifest refresh. Keep current-nest scoped commands such as `diff`, `foreach-*`, and `export` rooted where the user asked you to run them.

Only run `git-nest init --sure` to create a new nested nest when the user explicitly asks for one. `init --sure` (and `absorb-all`'s auto-init) always refuses, with no override, if the new nest's own subtree would contain a path already managed by an ancestor nest; the error names the conflicting ancestor and the exact `detach`/`init`/`absorb` recipe to resolve it. Follow that recipe rather than improvising a different fix.

Use porcelain output when a script or automation step needs stable records:

```sh
git nest status --recursive --porcelain
git nest outdated --recursive --porcelain
```

For `status --porcelain`, non-empty output means the current nest workspace is dirty or incomplete. For `outdated --porcelain`, non-empty output means newer subproject commits, missing checkouts, or remote query problems were found.

Use filtered foreach commands when you need to inspect or operate on a subset of checked-out subprojects:

```sh
git nest foreach-modified --porcelain
git nest foreach-clean --porcelain
git nest foreach-modified -- sh -c 'git status --short'
```

`foreach-modified` means dirty working trees. `foreach-clean` means clean checked-out subprojects.

Use `pull` to fast-forward clean, tracked subprojects to their upstream branch heads and record the result, instead of the older `foreach-clean -- git pull --ff-only` recipe:

```sh
git nest pull
git nest pull --sure          # also pulls the nest root
git nest pull --recursive     # also descends into nested nests
```

`pull` never force-merges: a dirty, detached-HEAD, no-upstream, or diverged subproject is skipped and reported by path with a fix-it command, and a network/fetch failure on one subproject does not stop the rest.

## Branching And Recording State

Use normal Git branch commands. `git-nest` can remember branch names locally, but it does not create, switch, push, or delete Git branches:

```sh
git switch -c feature/shared-cache
git nest branch-mark
git nest branch-list --verbose
```

After a subproject change is committed and pushed with Git, update the manifest:

```sh
git nest snapshot
git nest snapshot --dry-run
```

`snapshot` records clean, reproducible checked-out subproject commits. `snapshot --dry-run` prints manifest field changes without writing. `snapshot --check --strict` checks reproducibility without writing.

## Working Across Dirty Subprojects

There is no bulk "branch all" or "commit all" command. When the user wants to branch or commit every currently dirty subproject, use `foreach-modified`, which selects dirty checked-out subprojects and runs a command with the working directory set to each one. Only do this when the user asks, and prefer previewing first:

```sh
git nest foreach-modified --porcelain
```

Move each dirty subproject onto its own new branch, or commit each one:

```sh
git nest foreach-modified --continue-on-error -- git switch -c feature/shared-fix
git nest foreach-modified --continue-on-error -- sh -c 'git add -A && git commit -m "WIP in $GIT_NEST_SUBPROJECT_PATH"'
```

Use `sh -c` for multi-step commands so untracked files are staged (`git commit -am` stages only tracked changes). `--continue-on-error` keeps going after a per-subproject failure. git-nest exports `GIT_NEST_SUBPROJECT_PATH`, `GIT_NEST_BRANCH`, and `GIT_NEST_TARGET_BRANCH` into the command.

A commit makes the working tree clean, so a later `foreach-modified` will not re-select that subproject. Branch, commit, and push in a single pass, then record reproducible revisions:

```sh
git nest foreach-modified --continue-on-error -- \
  sh -c 'git switch -c feature/shared-fix && git add -A && git commit -m "WIP" && git push -u origin HEAD'
git nest snapshot
```

## Updating Nest Subprojects

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

## Changing Nest Shape

Only change project shape when the user explicitly asks. Prefer command-driven changes:

```sh
git nest absorb <path> <remote-url>   # outer-repo tracked files -> subproject
git nest absorb <path>                 # existing nested repo or submodule -> subproject
git nest inline <path>
git nest detach <path>
git nest remove <path>
git nest move <old-path> <new-path>
git nest move --url <new-url> <path>
```

`absorb` brings something already on disk into the nest as a managed subproject, auto-detecting the source. Outer-repository tracked files require a remote URL and support `--branch`, `--clone-mode`, `--preserve-history`, `--push`, `--message`, and `--force`; `--force` only overrides staged outer-repository changes under the path, not dirty files, untracked files, or non-empty remotes. A standalone nested repository records its own remote and current commit; a Git submodule is converted into a standalone managed subproject. `absorb` refuses a path that is already a subproject and refuses deeper nested repositories/submodules.

The three ways to take a subproject back out of the nest are distinct. `inline` dissolves the subproject into the outer repository as ordinary tracked files and discards its separate Git history (the remote is left untouched). `detach` removes the manifest entry but keeps the checkout as a standalone, still-ignored repository. `remove`/`rm` removes the manifest entry and deletes the checkout on disk; the retired `remove --keep-files` is rejected with guidance to use `detach`. `move`/`mv` moves a managed subproject path and updates `.gitnest` and `.gitignore`; `move --url` changes only the manifest URL and does not change the checkout remote. All of `absorb`, `inline`, `detach`, and `remove` support `--dry-run` and `--json`/`--json-pretty`. Inspect `git nest status` and `git status --short` before and after.

## Exporting Snapshots

Only export source snapshots when the user asks, especially if the export may include dirty working-tree content:

```sh
git nest export --output build/source.tar.gz --deterministic
git nest export --output build/source-dir --format dir
```

`export` writes `.gitnest`, a generated `MANIFEST.lock`, and tracked subproject working-tree files. It omits ignored files and strips `.git` directories unless `--include-git` is passed. It refuses dirty subprojects unless the user explicitly asks for `--allow-dirty`. Directory exports use shell file copying, `tar.gz` exports require system `tar`, and `zip` exports require `python` or `python3`.

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

Use `git nest restore --dry-run` and `git nest snapshot --dry-run` to preview the core mutating flows.

Ask before running commands that mutate repositories, push branches, install hooks, discard changes, or alter `.gitnest`.
