# git-nest

`git-nest` records and restores a reproducible workspace made from independent Git repositories.

```
git-nest 0.8.2 \\_oOO_//
```

A nest is a home for related repositories. Each subproject remains a normal Git repository with its own history, branches, remotes, and workflow. The outer repository records how those repositories belong together in `.gitnest`.

## Current 0.8 Capabilities

Since conception as a script dealing with submodules, `git-nest` has focused on making multi-repository workspaces explicit and reproducible without turning them into a monorepo.

It can:

- create a nest manifest with `init`, and refresh managed support files with `repair`;
- add, remove, move, and retarget subproject entries;
- clone an outer repository and restore its recorded subprojects;
- restore the filesystem from `.gitnest` with `restore`;
- snapshot clean, reproducible subproject commits back into `.gitnest`;
- inspect state with `status`, `verify`, `outdated`, `diff`, `log`, `list`, and `doctor`;
- discover unmanaged nested repositories and submodules with `discover`;
- update one subproject to a branch head, explicit revision, or tag;
- remember reusable branch names with local `branch-*` commands;
- install opt-in local hooks that help keep `.gitnest` current;
- bring files, repositories, and submodules into the nest with `absorb`, and take subprojects back out with `inline`, `detach`, and `remove`;
- export a source snapshot.

The tool does not replace normal Git commit, branch, review, or push workflows. Work in a subproject with Git, push that subproject when it is ready, then run `git-nest snapshot` so the outer manifest points at a reproducible commit.

## Requirements

- Git 2.20 or newer.
- A POSIX-like shell for `bin/git-nest` and the integration tests. Git Bash is the expected shell on Windows.
- `tar` for `git-nest export --format tar.gz`.
- `python` or `python3` for `git-nest export --format zip`; the implementation uses Python's standard `zipfile` module.
- Network and credentials only for commands that contact remotes, such as `add`, `restore`, `outdated`, `update`, and `snapshot` when it fetches.

## Installation And Invocation

### Windows

Install Git for Windows, then add this checkout's `bin` directory to `PATH`:

```bat
setx PATH "%PATH%;C:\path\to\git-nest\bin"
```

Open a new terminal after changing `PATH`.

Use either form:

```bat
git-nest version
git nest version
```

### Linux And macOS

Add the checkout's `bin/` directory to your shell startup file:

```sh
export PATH="$HOME/src/git-nest/bin:$PATH"
```

Or run directly from the checkout:

```sh
sh bin/git-nest version
```

### Shell Completion

```sh
git-nest completion bash > ~/.local/share/bash-completion/completions/git-nest
git-nest completion zsh  > ~/.zfunc/_git-nest
git-nest completion fish > ~/.config/fish/completions/git-nest.fish
```

## Workspace Model

`.gitnest` lives in the outer repository and records subproject paths, repository URLs, target branches, tags, and exact revisions.

Example:

```ini
[project]
version=1

[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=0123456789abcdef0123456789abcdef01234567

[subproject "libs/bar"]
repo=https://example.invalid/bar.git
tag=v1.2.3
revision=89abcdef0123456789abcdef0123456789abcdef
```

A recorded `revision` is the reproducibility contract. Another machine can clone the outer repository and run `git-nest restore` to materialize the same checked-out subproject commits.

Subprojects are ignored by the outer Git repository so their files do not get accidentally committed into the outer repo. The outer repo commits `.gitnest`; each subproject commits and pushes its own changes normally.

## Typical Workflows

### Create A Nest

```sh
mkdir product
cd product
git init
git-nest init
git-nest add https://example.invalid/libs/foo.git libs/foo
git add .gitnest .gitignore .gitattributes
git commit -m "Create nest"
```

### Work Without Hooks

```sh
# 1. Work normally inside a subproject.
cd libs/foo
git switch -c feature/foo-cache
# edit, test, commit
git push -u origin feature/foo-cache

# 2. From anywhere in the nest, update the manifest.
git-nest snapshot

# 3. Review and commit the outer manifest.
git diff .gitnest
git add .gitnest
git commit -m "Update foo revision"
git push
```

With no path argument, `snapshot` refreshes all managed subprojects. From inside a subproject, `git-nest snapshot .` refreshes only that subproject. From the nest root, `git-nest snapshot .` means the whole nest.

`snapshot` only records clean subprojects whose current commit is reachable from a reproducible source, such as an `origin/*` branch or a tag. Dirty or local-only commits are reported and skipped unless strict checking is requested.

### First Checkout

```sh
git clone https://example.invalid/product.git
cd product
git-nest restore
git-nest hooks-install
```

`restore` clones missing subprojects, fetches existing subprojects, and checks out the recorded revision or tag. It refuses unsafe local state unless a specific recovery option such as `--prune` or `--force` is used.

`git-nest clone <nest-repo-url>` is a convenience form for this first-checkout flow: it runs `git clone` for the nest repository and then runs `git-nest restore` when `.gitnest` exists. It is not a file-copy clone of an existing local checkout.

### Work With Hooks

Hooks are opt-in and local to the checkout:

```sh
git-nest hooks-install
```

With hooks installed, Git clients such as Lazygit, GitHub Desktop, and command-line Git can still do the normal commit and push work. The useful order is:

1. Commit and push changed subrepositories first.
2. Commit and push the nest root last.

Subproject hooks try to refresh the matching `.gitnest` entry when checkout or push activity makes the commit reproducible. Root hooks warn when the manifest may not describe the reproducible workspace you just tested.

Hooks are helpers, not authority. The manual workflow still works when hooks are not installed.

## Branch Memory

`git-nest` does not switch every repository to a coordinated branch. Use Git for branch changes:

```sh
git switch -c feature/shared-cache
git-nest branch-mark
```

Later, from anywhere in the nest:

```sh
git-nest branch-list
git-nest branch-list --verbose
git-nest branch-unmark feature/shared-cache
git-nest branch-cleanup
```

Branch marks are stored in `.gitnest-branches`, which is ignored by Git. Multiple branches may be marked for the same repository. `branch-cleanup` removes stale marks only; it does not delete Git branches.

## Working Across Dirty Subprojects

git-nest does not add bulk "branch all" or "commit all" commands. Use `foreach-modified`, which selects the currently dirty checked-out subprojects and runs a command inside each one. This keeps the behavior explicit and lets you use ordinary Git.

Preview which subprojects are dirty:

```sh
git-nest foreach-modified --porcelain
```

Move every dirty subproject onto its own new branch (one branch each):

```sh
git-nest foreach-modified --continue-on-error -- git switch -c feature/shared-fix
```

Use `git switch -C feature/shared-fix` instead if the branch may already exist and you want to reset it to the current commit. `--continue-on-error` keeps going when one subproject fails instead of stopping at the first.

Commit every dirty subproject (one commit each). Use `sh -c` so untracked files are staged too; `git commit -am` only stages already-tracked changes:

```sh
git-nest foreach-modified --continue-on-error -- sh -c 'git add -A && git commit -m "WIP in $GIT_NEST_SUBPROJECT_PATH"'
```

The command runs with its working directory set to each subproject, and git-nest exports context such as `GIT_NEST_SUBPROJECT_PATH`, `GIT_NEST_BRANCH`, and `GIT_NEST_TARGET_BRANCH`.

Because a commit makes the working tree clean, a later `foreach-modified` will no longer select that subproject. Do branch, commit, and push in a single pass, then record the reproducible revisions:

```sh
git-nest foreach-modified --continue-on-error -- \
  sh -c 'git switch -c feature/shared-fix && git add -A && git commit -m "WIP" && git push -u origin HEAD'
git-nest snapshot
git add .gitnest && git commit -m "Update subproject revisions"
```

## Commands

| Command | Brief use |
| --- | --- |
| `init [--rc] [--sure]` | Create a new `.gitnest`; `--sure` confirms an intentional nested nest inside an existing nest. |
| `repair [--rc]` | Refresh managed support files such as `.gitattributes`, `.gitignore`, and optional `.gitnest-rc`. |
| `add [--clone <full\|partial>] <repo> <path>` | Add and clone a subproject at a path relative to the current nest root; `.` is not valid. `--clone` records future `restore` clone mode and is unrelated to the `clone` command. |
| `remove` / `rm <path>` | Remove a managed subproject from the current nest and delete its checkout on disk; the remote is untouched. |
| `detach <path>` | Remove a managed subproject from the nest but keep its checkout as a standalone, ignored repository. |
| `move` / `mv <old-path> <new-path>` | Move a managed subproject path inside the current nest; `.` is not valid. |
| `move` / `mv --url <new-url> <path>` | Change a recorded subproject URL without moving files. |
| `clone <nest-repo-url> [target-dir]` | Run `git clone` for a nest repository, then automatically `restore` when `.gitnest` exists; it does not copy an existing local checkout. |
| `status` | Show local nest root and subproject state. |
| `outdated` | Check remotes for newer target-branch commits. |
| `verify` | Validate manifest entries, remotes, refs, clone mode, and checkout drift. |
| `diff` | Show subproject commits between recorded revisions and current checkouts. |
| `log` | Show combined nest and subproject history. |
| `list [--porcelain\|--json\|--json-pretty]` | List managed subprojects in a stable order with URL, target branch, revision, tag, checkout state, and reproducibility. |
| `discover [--max-depth <n>] [--exclude <name>]...` | Scan the current nest for unmanaged nested repositories and submodules and suggest a next step; discovery only. |
| `snapshot [<path>]` | Record clean, reproducible checked-out subproject commits. No path means all subprojects; `.` means all subprojects at the nest root and only the owning subproject inside one. |
| `restore` | Clone, fetch, and check out all subprojects in the current nest from `.gitnest`; it does not accept a path. |
| `freeze` | Pin tracked subprojects in the current nest to their current checkout commits. |
| `hooks-install` | Install managed local hooks in all checked-out repositories in the current nest. |
| `hooks-uninstall` | Remove managed local hooks from all checked-out repositories in the current nest. |
| `branch-mark [name]` | Remember a branch name for the current repository. |
| `branch-unmark <name>` | Remove a branch mark for the current repository. |
| `branch-list` | List remembered branch names and their repository paths. |
| `branch-cleanup` | Remove branch marks whose local branches no longer exist. |
| `foreach -- <command>` | Run a command in every checked-out subproject in the current nest. |
| `foreach-modified` | Run a command in dirty checked-out subprojects in the current nest or list them. |
| `foreach-clean` | Run a command in clean checked-out subprojects in the current nest or list them. |
| `config` | Read or update allowlisted manifest settings such as `clone-mode`, which controls future `restore` clones rather than the `clone` command. |
| `update <subproject>` | Move one clean managed subproject path to a target branch head, explicit revision, or tag; `.` is not valid. |
| `doctor` | Report environment and workspace health. |
| `completion` | Print shell completion scripts. |
| `export` | Export a source snapshot with `.gitnest` and `MANIFEST.lock`; `dir` uses shell copy, `tar.gz` requires system `tar`, and `zip` requires `python` or `python3`. |
| `absorb <path> [<url>]` | Bring something already on disk into the nest as a managed subproject, auto-detecting outer-repo files, a standalone nested repo, or a submodule. |
| `inline <path>` | Dissolve a managed subproject into the outer repo as ordinary tracked files. |
| `version` | Print the tool name, version, and logo. |

Run `git-nest help` for the grouped command overview, or `git-nest help <command>` for command-specific explanation and examples, such as `git-nest help snapshot` or `git-nest help branch-mark`.

## Hooks

`hooks-install` and `hooks-uninstall` can be run from anywhere in a nest. They apply to all checked-out repositories in the current nest: the nest root and its checked-out subprojects. They do not accept `--recursive`; nested nests manage their own hooks.

Installed hooks:

- root `post-checkout`: prints concise restore guidance for the nest path;
- root `pre-commit`: refreshes safe manifest entries and warns if `.gitnest` changed;
- root `pre-push`: checks whether the committed manifest describes reproducible subprojects and warns when it does not;
- subproject `post-checkout`: snapshots that subproject when its checkout is reproducible;
- subproject `pre-push`: records local push candidates for the root hooks to consider.

The root `post-checkout` output is intentionally concise:

```text
git-nest: manifest changed; run `git-nest restore` inside <path> to restore this nest.
```

## Nested Nests

Commands that require a nest walk toward the filesystem root until they find the nearest `.gitnest`. In filesystem terms this is walking to parent directories; in tree diagrams it is often described as moving toward the root.

A managed subproject may itself contain a `.gitnest`. Plain `git-nest init` inside a managed subproject refuses to create that nested nest by accident. Use:

```sh
git-nest init --sure
```

when the nested nest is intentional.

Recursive read commands such as `status`, `verify`, and `outdated` can include nested nests with `--recursive`. Write-side path commands stay within the current nest boundary.

## CI And Build Servers

A build that needs reproducible source should run:

```sh
git-nest restore
git-nest verify
```

For a copied-manifest startup, put `.gitnest` in an empty directory and run `git-nest restore`.

## Security Considerations

`.gitnest` contains repository URLs that `git-nest restore` will clone from. Review manifest changes with the same care as dependency files such as `package.json`, `go.mod`, or `requirements.txt`.

`git-nest` runs Git subcommands with manifest values and does not `eval` manifest content, but Git transports and credential helpers remain Git behavior. Avoid accepting manifest changes that redirect a subproject to an untrusted remote.

## Tests

Run the full integration suite from Git Bash or another POSIX-like shell:

```sh
sh tests/run-all-tests.sh
```

From Windows `cmd.exe`:

```bat
tests\run-all-tests.bat
```

The runner clears `${TMPDIR:-/tmp}/git-nest-test-workspaces`, runs each `tests/test_*.sh`, writes the Markdown summary `run-all-tests-results.md`, captures the full run to `run-all-tests.log`, and leaves numbered workspaces for inspection. The full suite can take more than 10 minutes on Windows.

By default the console shows a curated per-test narrative: a brief description of each step and each `git-nest` command with the output it produced. The full raw output of every command is saved per test and printed automatically when a test fails. The summary table sizes its columns to the longest test name.

Each test has a globally unique four-digit ID (the filename prefix). The runner accepts commands as well as options:

```sh
sh tests/run-all-tests.sh list                 # ID  description for every test
sh tests/run-all-tests.sh only 0130,0140,5010  # run only these IDs
sh tests/run-all-tests.sh except 5000,5010,5020 # run all but these IDs
sh tests/run-all-tests.sh help                 # commands and examples
```

Options: `--verbose` (`-v`) streams everything (full raw output with a shell trace) instead of the curated narrative; `--stop-on-fail` stops at the first failure; `--no-log` skips the full-run log and `--log FILE` writes it elsewhere. An unknown command, option, or test ID prints the help and stops. All commands and options work through `tests\run-all-tests.bat` too.

## AI User Skill

The repository includes `skills/git-nest/SKILL.md` for AI agents working in projects that use `git-nest`. It teaches agents how to inspect, restore, verify, edit, and prepare work in a project workspace without modifying the `git-nest` tool itself. Copy this skill into a consuming project's skill tree (for example `.agents/skills/git-nest/`, `.opencode/skills/git-nest/`, or `.claude/skills/git-nest/`) so its AI agents can load it.

Agents working on `git-nest` itself discover the same skill through `.agents/skills/git-nest/SKILL.md`, a thin pointer back to `skills/git-nest/SKILL.md`; the product copy under `skills/` stays the single source of truth.

## License

MIT License. See [LICENSE](LICENSE).
