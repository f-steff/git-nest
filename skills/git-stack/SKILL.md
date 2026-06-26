---
name: git-stack
description: Use git-stack in an application or firmware workspace that consumes the tool. Use when an AI agent needs to inspect, sync, verify, edit, test, or prepare changes in a project with a .stack manifest and nested stack modules, while avoiding modifications to the git-stack tool itself.
---

# git-stack

Use this skill when working in a project that already uses `git-stack`. The goal is to work safely in the consuming project, not to maintain `git-stack` itself.

## Hard Rules

- Do not modify `bin/git-stack`, `bin/git-stack.bat`, or `bin/git_stack.sh` unless the user explicitly asks to change the tool.
- Treat `.stack` as project coordination state. Prefer `git-stack` commands over manual edits.
- Do not run `git-stack upload`, push branches, install hooks, or finalize modules unless the user explicitly asks.
- Do not delete stack modules or rewrite branches to clean up unless the user explicitly asks.
- Preserve each repository boundary. A stack root commit and stack module commits are separate Git histories.

## Discovery

From anywhere inside a stack workspace, start with:

```sh
git stack version
git stack status
git stack available
git stack verify
git stack log --max-count 10
```

If `git stack` is not available, try:

```sh
git-stack version
sh bin/git-stack version
bin/git-stack.bat version
```

Use the command form already used by the project when possible.

## Normal Workflow

Before editing:

```sh
git stack sync
git stack status
git stack available
git stack verify
```

Use `sync` to fetch and restore stack modules recorded in `.stack`. Use `status` to understand stack root and module state. Use `verify` to catch missing modules, wrong remotes, unresolved refs, or checkout drift.

Use `available` when the user wants to know whether stack module remotes have newer target-branch commits without updating `.stack`, fetching local refs, or changing checkouts.

Use `log` as a read-only stack history view. It shows recent commits across the stack root and checked-out stack modules without fetching or rewriting history.

When changing code:

- Edit files in the repository that owns them.
- Shared source inside a stack module belongs to that stack module repository.
- Project glue, IDE project files, build scripts, and `.stack` usually belong to the stack root repository.
- Run project tests/builds from the stack root unless the project documents a different workflow.

After editing, inspect both stack root and module state:

```sh
git stack status
git status --short
git stack foreach -- git status --short
git stack log --max-count 10
```

## Nested Stacks

A stack module may itself contain a `.stack` file. By default, `git-stack` uses the nearest `.stack` found by walking upward from the current directory. If a command prints `Notice: nested stack found ...`, rerun with `--recursive` only when the user wants nested stacks included:

```sh
git stack status --recursive
git stack available --recursive
git stack verify --recursive
git stack sync --recursive
git stack log --recursive --max-count 20
```

Use porcelain output when a script or automation step needs stable records:

```sh
git stack status --recursive --porcelain
git stack available --recursive --porcelain
```

For `status --porcelain`, non-empty output means the stack workspace is dirty or incomplete. For `available --porcelain`, non-empty output means newer module commits, missing checkouts, or remote availability problems were found.

## Branching

Only start coordinated branches when the user asks:

```sh
git stack start XX-123-short-description
```

Use `git stack start .` when the user wants `git-stack` to record current branches without creating or switching branches.

If dirty files exist, ask before choosing `--stash-dirty`, `--discard-dirty`, or cancellation. Do not discard work automatically.

## Preparing Review State

Use this only when the user asks to prepare or publish work:

```sh
git stack refresh
git stack upload
git stack upload --finalize
git stack check
```

`refresh` updates local manifest state without pushing. `upload` pushes changed module branches and records pending module state in `.stack`. `upload --finalize` pushes changed module branches and records the pushed commits directly as finalized revisions when the user does not want a separate review/finalize step. `check` fails while pending modules remain.

`git-stack` does not create pull requests by itself. If the project uses provider tooling, create PRs only when the user asks, commonly after upload:

```sh
git stack foreach-modified -- az repos pr create ...
```

## Updating Stack Modules

Only change module versions when the user asks. Prefer command-driven updates:

```sh
git stack update libs/foo --remote
git stack update libs/foo --revision <sha>
git stack update libs/foo --tag <tag>
git stack update libs/foo --branch release/1 --remote
```

Use `--no-fetch` only when the caller intentionally wants local refs without fetching.

After an update, inspect `.stack` and run:

```sh
git stack verify
```

## Finalizing Pending Modules

Only finalize when the user says a module change is approved or merged:

```sh
git stack finalize libs/foo --revision <sha>
git stack finalize libs/foo --tag v1.2.3
git stack finalize libs/foo --use-target-head
git stack check
```

Use explicit `--revision` or `--tag` when known. Avoid relying on auto-finalize if there is any ambiguity.

## IDE And Build Hooks

Some consuming projects call `bin/git-stack.bat` from IDE build or post-build steps because it is polyglot: `cmd.exe` executes the batch section, while `sh`/Bash executes the shell fallback. This lets one project configuration work across Windows, Linux, and macOS.

Do not remove or replace those calls casually. If a build hook fails, first verify the tool is available and the workspace is a valid stack:

```sh
bin/git-stack.bat version
bin/git-stack.bat status
```

## When In Doubt

Prefer read-only commands first:

```sh
git stack status
git stack available
git stack verify
git stack foreach -- git status --short
```

Ask before running commands that mutate repositories, push branches, install hooks, finalize modules, discard changes, or alter `.stack`.
