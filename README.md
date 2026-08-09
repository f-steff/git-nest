# git-nest   `\\_oOO_//`

git-nest pins your multi-repo workspace as a manifest in your own repository -- versioned like your code, restorable on any machine.

git-nest is a thoughtful tool that solves a real problem: coordinating multiple independent Git repositories without submodules, monorepo pain, or heavy dependencies.

The nest is a home for related repositories. Each subproject remains a normal Git repository with its own history, branches, remotes, and workflow. The outer repository records how those repositories belong together in the `.gitnest` manifest.

Conceptually, the nest is to Git what a package manifest is to a language ecosystem: like Go modules, Python packages, or NuGet packages, but for whole Git repositories. The `.gitnest` file is the manifest that pins exactly which repository lives at which path and revision.

## Current Capabilities

Since conception as a script dealing with submodules, `git-nest` has focused on making multi-repository workspaces explicit and reproducible without turning them into a monorepo.

It can:

- create a nest manifest with `init`, and refresh managed support files with `tidy`;
- add, remove, move, and retarget subproject entries;
- clone an outer repository and restore its recorded subprojects;
- restore the filesystem from `.gitnest` with `restore`, and fast-forward clean subprojects to their upstream branch heads with `pull`;
- snapshot clean, reproducible subproject commits back into `.gitnest`;
- inspect state with `status`, `verify`, `outdated`, `diff`, `log`, `list`, `tree`, and `doctor`;
- bring files, repositories, submodules, git-subrepos, and subtrees into the nest with `absorb` (including `--subrepo`/`--subtree`), and take subprojects back out with `inline`, `detach`, and `remove`;
- discover unmanaged nested repositories, submodules, and git-subrepos with `survey`, and bring every detected submodule and nested repo in at once with `absorb-all`;
- update one subproject to a branch head, explicit revision, or tag;
- remember reusable branch names with local `branch-*` commands;
- install opt-in local hooks that help keep `.gitnest` current;
- export a source snapshot.

The tool does not replace normal Git commit, branch, review, or push workflows. Work in a subproject with Git, push that subproject when it is ready, then run `git-nest snapshot` so the outer manifest points at a reproducible commit.

See [`docs/examples.md`](docs/examples.md) for walkthroughs of these workflows with real commands and output.

Because `.gitnest` is a plain-text, human-readable file, every step the tool performs can also be carried out by hand: the file lists the repository URLs and pinned revisions, and a manual `git clone` and `git checkout` reproduce the same workspace. `git-nest` exists to make that bookkeeping fast and reliable, not to hide it.

## Requirements

### Running git-nest

- Git 2.20 or newer.
- A POSIX-like shell for `bin/git-nest`. Git Bash is the expected shell on Windows.
- For specific operations only:
  - `tar` for `git-nest export --format tar.gz`.
  - `python` or `python3` for `git-nest export --format zip`; the implementation uses Python's standard `zipfile` module.
  - `git-filter-repo` for `git-nest absorb --preserve-history`.
- Network and credentials only for commands that contact remotes, such as `add`, `restore`, `outdated`, `update`, and `snapshot` when it fetches.

### Developing git-nest

The runtime requirements above apply, plus a shell that can run the test
suite (`sh tests/run-all-tests.sh`). The optional Docker cross-shell matrix
needs a local Docker install -- see
[`development/ci_and_dockerized_testing.md`](development/ci_and_dockerized_testing.md) and
[`development/README.md`](development/README.md) for the full development setup.
Docker is only needed to verify portability across many shells; the regular
suite runs without it.

### Backend Requirements

There are no special backend requirements. git-nest does only require a standard git server.

## Known Windows Limitation

On Windows, starting a Git process costs roughly 40 ms instead of the ~1 ms
seen on Linux or macOS. For interactive use this is hardly noticeable --
every git-nest command still completes in a moment, and the same commands
run everywhere. The gap only becomes visible when running the full automated
test suite, which issues several hundred git-nest commands and therefore
takes about 40 minutes on Windows versus ~2.5 minutes on Linux. CI accounts
for this with a fast platform-focused test set; see
[`development/ci_and_dockerized_testing.md`](development/ci_and_dockerized_testing.md)
for the measured numbers.

## Installation And Invocation

Install the latest release from any POSIX shell (Linux, macOS, BSD, Git
Bash):

```sh
curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
```

Pin a specific version:

```sh
VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
```

Windows (cmd.exe or PowerShell) -- the `-ExecutionPolicy Bypass` flag makes
the one-liner work regardless of the machine's PowerShell execution
policy:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex }"
```

Pinned version on Windows:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:VERSION='0.8.16'; iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex"
```

The installers download the release archive, verify it against the
release's `SHA256SUMS`, and install into `$HOME/.local`
(POSIX) or `%USERPROFILE%\.local` (Windows). The `bin/` directory inside
that prefix is the only thing that needs to be on `PATH`. Configuring
PATH is the installer's default behavior:

- POSIX (`git-nest-install.sh`): appends `export PATH="$HOME/.local/bin:$PATH"`
  to your shell startup file (`~/.profile`, `~/.bashrc`, or `~/.zshrc`).
  Pass `--no-add-path` to only print the line.
- Windows (`git-nest-install.ps1` / `.bat`): adds
  `%USERPROFILE%\.local\bin` to the user PATH and registers git-nest in
  Apps & Features (Settings -> Apps). Pass `--no-add-path` (bat) or
  `GIT_NEST_ADD_PATH=0` (ps1) to leave PATH untouched.

CI pipelines that manage PATH themselves (e.g. `$GITHUB_PATH`) should
install with `--no-add-path` / `GIT_NEST_ADD_PATH=0`.

The installers copy their own uninstaller into the same `bin/` directory,
and `git-nest help` prints the install location. To install into a
different prefix, use `--prefix DIR` (sh/bat) or `GIT_NEST_PREFIX=DIR`
(ps1); the uninstaller must then be told the same prefix.

### Installed Layout

Everything lives under the install prefix (`$HOME/.local` on POSIX,
`%USERPROFILE%\.local` on Windows):

```text
<prefix>/
|-- bin/                        the payload; this directory goes on PATH
|   |-- git-nest                the shell entrypoint (all platforms)
|   |-- git-nest-main.sh             shared implementation
|   |-- git-nest.bat            cmd.exe launcher        (Windows only)
|   |-- git-nest.ps1            PowerShell launcher     (Windows only)
|   |-- git-nest-install.sh     installer, kept for re-installs
|   |-- git-nest-install.bat    installer                (Windows only)
|   |-- git-nest-install.ps1    installer                (Windows only)
|   |-- git-nest-uninstall.sh   uninstaller (on PATH)
|   |-- git-nest-uninstall.bat  uninstaller             (Windows only)
|   |-- git-nest-uninstall.ps1  uninstaller             (Windows only)
|   `-- lib/                    library modules
|       |-- git-nest-commands.sh
|       |-- git-nest-conversion.sh
|       |-- git-nest-doctor.sh
|       |-- git-nest-hooks.sh
|       |-- git-nest-manifest.sh
|       |-- git-nest-parse.awk
|       `-- git-nest-tree-render.awk
`-- share/                      staged content from the release
    |-- doc/git-nest/           raw markdown docs + generated HTML
    |-- git-nest/skill/         AI usage skill (SKILL.md)
    `-- man/                    man pages (man1 + man5)
```

Differences by installer:

- `git-nest-install.sh` (POSIX) installs `bin/` + `share/` as above and
  skips the Windows-only launchers.
- `git-nest-install.ps1` (Windows, macOS, Linux) installs the same tree;
  on Windows `git-nest.bat`/`git-nest.ps1` are included.
- `git-nest-install.bat` (cmd.exe) installs the Windows launchers + `lib/`
  and the docs (markdown + HTML), skipping man pages.

### Uninstalling

The uninstaller is copied into the installed `bin/` directory, so it is on
PATH like the tool itself. Uninstall exactly what you installed:

- **Linux, macOS, BSD (POSIX shell)** -- `git-nest-uninstall.sh` (or
  `sh "$HOME/.local/bin/git-nest-uninstall.sh"` if PATH was not
  configured). Removes `bin/`, `share/`, and the `export PATH=...` line
  the installer added to your shell startup file.
- **Windows (PowerShell)** -- `git-nest-uninstall.ps1`. Removes `bin/`,
  `share/`, the user PATH entry, and the Apps & Features registration.
- **Windows (cmd.exe)** -- `git-nest-uninstall.bat`. Same removals; use
  `--remove-path current|system` to clean only the current session or the
  system PATH instead of the user PATH.

The uninstaller finds its own installation (the directory it sits in), so
no flags are needed for the default layout. On Windows, git-nest also
appears under Settings -> Apps -> Installed apps; the "Uninstall" button
runs the same uninstaller. `git-nest help` prints the install location.

For a custom prefix, pass the same prefix you installed with: `sh
/path/to/bin/git-nest-uninstall.sh --prefix DIR` (or set
`GIT_NEST_PREFIX=DIR` for the PowerShell variant).

Or use git-nest directly from a checkout:

```sh
sh bin/git-nest version
```

Once `bin/` is on `PATH`, the entrypoint is available under all three names
(`git-nest`, the `.bat` polyglot on Windows, and the `.ps1` PowerShell
launcher), and Git's subcommand discovery finds it as `git nest`.

Use either form:

```bat
git-nest version
git nest version
```

From PowerShell 7+ (`pwsh`), the `.ps1` launcher is also on `PATH`:

```powershell
git-nest.ps1 version
```

### Shell Completion

```sh
git-nest completion bash > ~/.local/share/bash-completion/completions/git-nest
git-nest completion zsh  > ~/.zfunc/_git-nest
git-nest completion fish > ~/.config/fish/completions/git-nest.fish
```

From PowerShell 7+ (dot-source the generated script):

```powershell
git-nest completion powershell | Out-File -Encoding utf8 ~/git-nest-completion.ps1
. ~/git-nest-completion.ps1
```

For yash, place the generated file in your completion load path:

```sh
git-nest completion yash > ~/.yash/completion/git-nest
```

## Workspace Model

`.gitnest` lives in the outer repository and records subproject paths, repository URLs, target branches, tags, and exact revisions.

Subprojects can live at any valid folder inside the outer repository. A plain
directory such as `libs/` or `libs/displaydriver/` can group several
subprojects without itself being a repository:

```
product/                                <- outer repository (git init)
+-- .gitnest                            <- the manifest, committed to the outer repo
+-- apps/
|   +-- frontend/                       <- subproject: its own Git repository
|   +-- fubar/                          <- subproject: its own Git repository
+-- libs/
|   +-- displaydriver/
|       +-- bar/                        <- subproject: its own Git repository
|       +-- foo/                        <- subproject: its own Git repository
+-- src/                                <- ordinary outer-repo files (tracked)
```

Each subproject is an ordinary Git repository with its own commits, branches,
and remote; `.gitnest` only records the exact revision the outer workspace is
currently reproducible at.

A managed subproject may itself contain a `.gitnest`, making it a nested nest:
the subproject stays an ordinary subproject of the outer nest while also being
its own nest with its own subprojects:

```
product/                                <- outer repository (git init)
+-- .gitnest                            <- outer manifest, committed to the outer repo
+-- libs/
|   +-- bar/                            <- subproject: its own Git repository
|   +-- foo/                            <- subproject AND its own nest
|       +-- .gitnest                    <- nested nest manifest
|       +-- widgets/                    <- subproject of the nested nest
+-- src/                                <- ordinary outer-repo files (tracked)
```

See "Nested Nests" below for how commands treat these workspaces.

Example:

```ini
[project]
version=1

[subproject "libs/displaydriver/foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=0123456789abcdef0123456789abcdef01234567

[subproject "libs/displaydriver/bar"]
repo=https://example.invalid/bar.git
tag=v1.2.3
revision=89abcdef0123456789abcdef0123456789abcdef
```

A recorded `revision` is the reproducibility contract. Another machine can clone the outer repository and run `git-nest restore` to materialize the same checked-out subproject commits.

Subprojects are ignored by the outer Git repository so their files do not get accidentally committed into the outer repo. The outer repo commits `.gitnest`; each subproject commits and pushes its own changes normally.

## `.gitnest` File Syntax

`.gitnest` is a plain-text, INI-like format: bracketed section headers, one `key=value` pair per line, blank lines and `#`-prefixed comment lines ignored anywhere. A `[project]` section with `version=1` is required, followed by one `[subproject "<path>"]` section per managed subproject. The `revision` key in a subproject is the reproducibility contract: it pins the exact commit another machine restores.

See [`docs/manifest.md`](docs/manifest.md) for the complete key reference and the validation rules (`validate_manifest_schema`). In brief: `repo` is required per subproject, `target_branch` and `revision` are the usual recorded state, and `clone`/`depth`/`tag` are optional refinements. Keys not listed there are preserved verbatim across manifest rewrites so external tooling can add its own extension data (see [`development/technical_docs.md`](development/technical_docs.md) for the exact preservation contract).

## Typical Workflows

See [`docs/examples.md`](docs/examples.md) for a fuller set of walkthroughs (absorbing existing repositories, submodules, git-subrepos, and subtrees; surveying and bulk-absorbing an unmanaged tree; nested nests; pulling; visualizing a nest with `tree`; and more), each with real commands and output.

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

With hooks installed, `.gitnest` is updated automatically, even when you use
GUI Git clients such as Lazygit or GitHub Desktop. The hooks sit inside each
repository's own hooks directory, so any client that runs normal Git commit or
push work triggers them; you do not need to remember to run `git-nest
snapshot` yourself.

Hooks are opt-in and local to the checkout:

```sh
git-nest hooks-install
```

Any Git client -- Lazygit, GitHub Desktop, or command-line Git -- keeps
working normally for commit and push. The useful order is:

1. Commit and push changed subrepositories first.
2. Commit and push the nest root last.

Subproject hooks try to refresh the matching `.gitnest` entry when checkout or push activity makes the commit reproducible. Root hooks warn when the manifest may not describe the reproducible workspace you just tested.

Hooks are helpers, not authority. The manual workflow still works when hooks are not installed.

## Branch Memory

Branch memory is a convenient notebook: from anywhere inside the nest, you can
always look up a branch name you recorded elsewhere. When a feature touches
several repositories at once, `branch-*` keeps one name -- e.g.
`feature/shared-cache` -- reachable no matter which subproject you happen to be
in.

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

`foreach` and `foreach-modified` run only inside subprojects, never the nest root. When a feature also changes the nest root itself, drive the root with ordinary Git (`git switch -c feature/shared-fix`, commit, push) as a separate step, and use `git-nest branch-mark` in each participating repository if you want a local record of which branch belongs to the feature. Branch memory is only a notepad; it does not switch, push, or delete branches.

## Updating Subprojects On Their Current Branch

To pull upstream changes into the subprojects that are already checked out on a branch, without rewriting their state from `.gitnest`, fan out an ordinary fast-forward-only pull over the clean subprojects:

```sh
git-nest foreach-clean -- git pull --ff-only
```

`foreach-clean` selects only subprojects with a clean working tree, so dirty subprojects are skipped rather than disturbed. `--ff-only` refuses to create a merge commit: any subproject whose branch has diverged from its upstream is reported and left untouched for you to rebase or merge by hand. Add `--continue-on-error` to attempt every clean subproject and still report the ones that could not fast-forward:

```sh
git-nest foreach-clean --continue-on-error -- git pull --ff-only
```

This is a working-tree convenience, not a manifest authority. It does not replace `restore` (which reconciles checkouts to `.gitnest`) or `snapshot` (which records revisions back into `.gitnest`). After pulling, run `git-nest snapshot` if you want the manifest to point at the new commits. As with the other recipes, the nest root is not included; pull it separately with ordinary Git.

## Commands

| Command | Brief use |
| --- | --- |
| `init [--rc] [--sure]` | Create a new `.gitnest`; `--sure` confirms an intentional nested nest inside an existing nest. Also creates `NEST_README.md` (a short pointer for anyone who clones the nest) if it does not exist. |
| `tidy [--rc]` | Refresh managed support files such as `.gitattributes`, `.gitignore`, and optional `.gitnest-rc`. |
| `add [--clone <full\|partial\|shallow>] [--depth <n>] <repo> <path>` | Add and clone a subproject at a path relative to the current nest root; `.` is not valid. `--clone` records future `restore` clone mode; `--depth` sets shallow clone depth (default 1). |
| `remove` / `rm [--force] [--dry-run] [--json\|--json-pretty] <path>` | Remove a managed subproject from the current nest and delete its checkout on disk; the remote is untouched. |
| `detach [--dry-run] [--json\|--json-pretty] <path>` | Remove a managed subproject from the nest but keep its checkout as a standalone, ignored repository. |
| `move` / `mv <old-path> <new-path>` | Move a managed subproject path inside the current nest; `.` is not valid. |
| `move` / `mv --url <new-url> <path>` | Change a recorded subproject URL without moving files. |
| `clone <nest-repo-url> [target-dir]` | Run `git clone` for a nest repository, then automatically `restore` when `.gitnest` exists; it does not copy an existing local checkout. |
| `status [--recursive] [--porcelain\|--json\|--json-pretty] [--exit-code]` | Show local nest root and subproject state. |
| `outdated [--recursive] [--porcelain\|--json\|--json-pretty]` | Check remotes for newer target-branch commits. |
| `pull [--recursive] [--sure] [--no-fetch] [--dry-run] [--json\|--json-pretty]` | Fast-forward clean subprojects to their upstream branch head and snapshot the result; `--sure` also pulls the nest root, `--recursive` descends into nested nests. |
| `verify` | Validate manifest entries, remotes, refs, clone mode, and checkout drift. |
| `diff` | Show subproject commits between recorded revisions and current checkouts. |
| `log` | Show combined nest and subproject history. |
| `list [--porcelain\|--json\|--json-pretty] [--redact]` | List managed subprojects in a stable order with URL, target branch, revision, tag, checkout state, and reproducibility; `--redact` strips URL credentials and home paths. |
| `survey [--max-depth <n>] [--exclude <name>]... [--include <path>]... [--porcelain\|--json\|--json-pretty]` | Scan the current nest for unmanaged nested repositories, submodules, and git-subrepos and suggest a next step; detection only. |
| `tree [--all] [--recursive] [--plain] [--porcelain\|--json\|--json-pretty]` | Display an ASCII-art tree of the current nest grouped by shared path prefixes; `--all` also shows unmanaged findings. |
| `snapshot [<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]` | Record clean, reproducible checked-out subproject commits. No path means all subprojects; `.` means all subprojects at the nest root and only the owning subproject inside one. `--check`/`--strict` validate without writing; `--recursive` descends into nested nests. |
| `restore [--recursive] [--prune] [--force] [--dry-run] [--depth <n>]` | Clone, fetch, and check out all subprojects in the current nest from `.gitnest`; `--depth` overrides per-project shallow clone depth, `--prune` removes reviewed stale paths. |
| `freeze [--force] [--only <path>[,<path>...]] [--dry-run]` | Pin tracked subprojects in the current nest to their current checkout commits; `--force` freezes dirty subprojects, `--only` limits to a comma-separated path list. |
| `gc [--aggressive] [--dry-run] [--json\|--json-pretty]` | Run git gc in the nest root and every checked-out subproject; `--aggressive` passes `--aggressive` to git gc. |
| `hooks-install` | Install managed local hooks in all checked-out repositories in the current nest. |
| `hooks-uninstall` | Remove managed local hooks from all checked-out repositories in the current nest. |
| `branch-mark [name]` | Remember a branch name for the current repository. |
| `branch-unmark <name>` | Remove a branch mark for the current repository. |
| `branch-list` | List remembered branch names and their repository paths. |
| `branch-cleanup` | Remove branch marks whose local branches no longer exist. |
| `foreach [--include-root-first\|--include-root-last] [--only-nested\|--no-nested] [-- <command> [args...]]` | Run a command in every checked-out subproject in the current nest; `--include-root-first`/`--include-root-last` also run it on the nest root, `--only-nested`/`--no-nested` filter by whether the subproject is itself a git-nest workspace. |
| `foreach-modified [--continue-on-error] [--only-nested\|--no-nested] [--porcelain\|--json\|--json-pretty] [-- <command> [args...]]` | Run a command in dirty checked-out subprojects in the current nest or list them. |
| `foreach-clean [--continue-on-error] [--only-nested\|--no-nested] [--porcelain\|--json\|--json-pretty] [-- <command> [args...]]` | Run a command in clean checked-out subprojects in the current nest or list them. |
| `config` | Read or update allowlisted manifest settings such as `clone-mode`, which controls future `restore` clones rather than the `clone` command. |
| `update [--remote\|--target-head\|--revision <sha-or-ref>\|--tag <tag>] [--branch <branch>] [--no-fetch] <subproject>` | Move one clean managed subproject path to a target branch head, explicit revision, or tag; `.` is not valid. |
| `doctor [--json\|--json-pretty] [--online\|--offline] [--timeout <seconds>] [--exit-code] [--redact]` | Report environment and workspace health; `--redact` strips URL credentials and home paths from the output, `--exit-code` returns nonzero for warnings or errors. |
| `completion <bash\|zsh\|fish\|yash\|powershell>` | Print a shell completion script to stdout. |
| `export --output <path> [--format <tar.gz\|zip\|dir>] [--include-git] [--deterministic] [--allow-dirty]` | Export a source snapshot with `.gitnest` and `MANIFEST.lock`; `dir` uses shell copy, `tar.gz` requires system `tar`, and `zip` requires `python` or `python3`. |
| `absorb <path> [<url>]` | Bring something already on disk into the nest as a managed subproject, auto-detecting outer-repo files, a standalone nested repo, or a submodule. |
| `absorb-all [--sure] [--force-partial] [--dry-run] [--max-depth <n>] [--exclude <name>]... [--include <path>]... [--json\|--json-pretty]` | Scan like `survey` and absorb every detected submodule and nested repo, deepest path first; never absorbs git-subrepos or subtrees. |
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

### Continuous Integration

CI runs on GitHub Actions as six manual-only workflows -- a fast,
platform-focused subset and the full test suite, each on Linux, macOS, and
Windows. The fast subset covers unit tests, static analysis, the platform
tests (launchers, completions, git invocation), export formats, and
paths-with-spaces -- everything that can genuinely differ per platform --
since Windows process startup makes the full suite about 19x slower there
(~40 min) than on Linux (~2.5 min). See
[`development/ci_and_dockerized_testing.md`](development/ci_and_dockerized_testing.md)
for the workflow reference, measured timings, and how to trigger a run.

The CI status badges are shown on the [GitHub Pages start page]
(https://f-steff.github.io/git-nest/).

## Security Considerations

`.gitnest` contains repository URLs that `git-nest restore` will clone from. Review manifest changes with the same care as dependency files such as `package.json`, `go.mod`, or `requirements.txt`.

`git-nest` runs Git subcommands with manifest values and does not `eval` manifest content, but Git transports and credential helpers remain Git behavior. Avoid accepting manifest changes that redirect a subproject to an untrusted remote.

## Repository Layout

git-nest ships as plain POSIX shell, split by responsibility rather than as one large script:

| Path | Role |
|------|------|
| `bin/git-nest` | Thin POSIX entrypoint. Locates and sources `git-nest-main.sh`, then dispatches into it. Keep this file small; put real behavior in the library modules below. |
| `bin/git-nest.ps1` | PowerShell 7+ launcher. On Windows finds Git Bash then forwards; on Linux/macOS runs via `/bin/sh`. |
| `bin/git-nest.bat` | Polyglot Windows launcher: runs from `cmd.exe` and from sh/bash contexts alike, then forwards to `bin/git-nest` through Git Bash. |
| `bin/git-nest-main.sh` | Main shared implementation entrypoint. Defines shared constants and sources every module in `bin/lib/`; the command dispatch table (`git_nest_main`) lives in `bin/lib/git-nest-commands.sh`. |
| `bin/lib/git-nest-manifest.sh` | Core manifest reading/writing, the manifest cache, path-safety and boundary guards, `.gitignore`/`.gitattributes` hygiene, locking, and other helpers shared across every command. |
| `bin/lib/git-nest-commands.sh` | Command implementations not covered by the other modules: `init`, `add`, `remove`, `move`, `status`, `outdated`, `verify`, `diff`, `log`, `list`, `restore`, `snapshot`, `pull`, `freeze`, `foreach*`, `branch-*`, `config`, `update`, help text, and shell completions. |
| `bin/lib/git-nest-conversion.sh` | Nest-boundary conversions: `export`, `absorb` (all sources, including `--subrepo`/`--subtree`), and `inline`, plus the shared recovery-backup infrastructure the destructive conversions use. |
| `bin/lib/git-nest-doctor.sh` | Read-only diagnostics: `doctor`, `survey`, and `tree`, plus the reproducibility-state classification `list` uses. |
| `bin/lib/git-nest-hooks.sh` | Managed local Git hook installation, removal, and preflight (`hooks-install`/`hooks-uninstall`). |
| `bin/lib/git-nest-parse.awk` | Single-pass `.gitnest` parser used by the manifest cache: emits shell-assignable variable declarations for `eval`, avoiding a subprocess per key read. |
| `bin/lib/git-nest-tree-render.awk` | Renders `tree`'s flat, pre-sorted row list as an ASCII-art tree grouped by shared path prefixes. |
| `bin/.shellcheckrc` | ShellCheck configuration and the small set of justified, commented suppressions for this codebase. |
| `docs/` | User-facing and technical documentation: the behavior contract, technical notes, exit codes, and maintainer guidance. |
| `docs/command-behavior-contract.md` | The behavior contract: what every command does and guarantees. |
| `docs/manifest.md` | Reference specification for the `.gitnest` manifest format (INI schema, keys, validation rules). |
| `docs/howto.md` | Step-by-step recipes for multi-step scenarios (e.g. moving a subproject between nests). |
| `schemas/` | JSON output schema (`git-nest-output-v1.schema.json`) used by `--json`/`--json-pretty` output. |
| `skills/git-nest/SKILL.md` | The portable AI-agent usage skill shipped to projects that consume git-nest (see "AI User Skill" below). |
| `tests/` | The shell-based test suites and their runners; see "Tests" below. |
| `tests/integration-tests/` | End-to-end integration tests (real Git repositories) plus `helper.sh` and `check.sh`. |
| `tests/unit-tests/` | Function-level unit tests with a mock Git shim and their standalone runner. |

The library modules in `bin/lib/` share plain global shell variables rather than function-local state (this is plain POSIX `sh`, which has no reliable cross-shell `local`), so a handful of common names (`path`, `repo`, `old_path`, `new_path`, and similar) are deliberately reused across call chains. When adding a new helper, prefer a short, unique prefix for its own working variables (as most of the existing helpers already do) rather than a generic name that a caller might also be holding onto across the call.

## Tests

Two suites live under `tests/` -- an end-to-end integration suite (real Git
repositories) and a function-level unit suite (mock Git shim) -- plus a
Docker cross-shell runner:

```
tests/
  run-all-tests.sh            main runner (IDs 0000-5050)
  run-all-tests.bat           cmd.exe launcher
  tests.md                    overall test strategy guide
  docker/                     cross-shell checks in Alpine + Debian
  unit-tests/                 function-level suite (mock Git shim)
  integration-tests/          end-to-end suite (real Git repositories)
```

Run the full suite from Git Bash or another POSIX-like shell:

```sh
sh tests/run-all-tests.sh
```

From Windows `cmd.exe`:

```bat
tests\run-all-tests.bat
```

The runner cleans its workspace and stale artifacts at startup, writes the
Markdown summary `run-all-tests-results.md`, captures the full run to
`run-all-tests.log`, and leaves numbered workspaces for inspection. The
`cleanup` command removes those artifacts without running tests. The full
suite can take more than 30 minutes on Windows.

See [`tests/tests.md`](tests/tests.md) for the full test guide: the two
suites and how they fit together, how to run individual tests (`only`,
`except`, `list`), the helper API, ID allocation, and debugging tips.
See [`tests/unit-tests/unit-tests.md`](tests/unit-tests/unit-tests.md) for
the unit test guide (mock Git, assertions, coverage tracking).

## Troubleshooting

### "Could not acquire manifest lock" error

Another `git-nest` process is holding the `.gitnest.lock` directory. Wait for it to finish, or if no `git-nest` process is running, remove the stale lock:

```sh
rm -rf .gitnest.lock
```

### "fetch failed" during restore or snapshot

Check network access and authentication for the subproject remote. Run `git-nest doctor` for a health report:

```sh
git-nest doctor
```

If the remote is unreachable, use `--no-fetch` or `--offline` for commands that support it.

### .gitnest schema error after manual edit

If you hand-edited `.gitnest` and `git-nest` rejects it, check for:
- Missing `[project]` section with `version=1`
- Duplicate section names
- Trailing whitespace or malformed `key=value` lines
- Backslashes in paths instead of forward slashes

Run `git-nest doctor` for a schema validation report.

### "Recovery backup" leftover after interrupted conversion

If a conversion (`inline`, `absorb --preserve-history`, `absorb-all`) was interrupted, a `.gitnest-recovery-*` directory remains. Open its `RECOVERY.txt` for restore instructions. Clean up with:

```sh
rm -rf .gitnest-recovery-*
```

Run `git-nest doctor` to check for leftover recovery backups.

### Test suite hangs

The test runner has a watchdog (default 180 seconds per test without output). If a test hangs, increase the timeout:

```sh
TEST_WATCHDOG_SECONDS=300 sh tests/run-all-tests.sh
```

## Further Reading

- [`docs/command-behavior-contract.md`](docs/command-behavior-contract.md) --
  the authoritative behavior contract for every command.
- [`docs/manifest.md`](docs/manifest.md) -- the `.gitnest` format and its
  validation rules.
- [`docs/examples.md`](docs/examples.md) -- walkthroughs of the workflows
  above with real commands and output.
- [`docs/howto.md`](docs/howto.md) -- recipes for multi-step scenarios such
  as moving a subproject between a nest and a nested nest.
- [`docs/ci-consumer-guide.md`](docs/ci-consumer-guide.md) -- for DevOps
  engineers integrating git-nest into CI pipelines on any system.
- [`development/technical_docs.md`](development/technical_docs.md) --
  implementation architecture, the manifest cache, concurrency, and the
  preservation contract.
- [`docs/exit-codes.md`](docs/exit-codes.md) -- the shared exit-code table.
- [`development/ci_and_dockerized_testing.md`](development/ci_and_dockerized_testing.md) --
  the GitHub Actions workflows and the Docker cross-shell test runner.
- [`tests/tests.md`](tests/tests.md) and
  [`tests/unit-tests/unit-tests.md`](tests/unit-tests/unit-tests.md) -- the
  test suites.
- [`development/README.md`](development/README.md) -- for contributors
  working on git-nest itself.
- [`todo.md`](todo.md) -- planned work, postponed ideas, and things git-nest
  deliberately will not do.

## Contributing And Maintenance

See [`version.md`](version.md) for the full version history and changelog.

## AI User Skill

The repository includes `skills/git-nest/SKILL.md` for AI agents working in projects that use `git-nest`. It teaches agents how to inspect, restore, verify, edit, and prepare work in a project workspace without modifying the `git-nest` tool itself. Copy this skill into a consuming project's skill tree (for example `.agents/skills/git-nest/`, `.opencode/skills/git-nest/`, or `.claude/skills/git-nest/`) so its AI agents can load it.

Agents working on `git-nest` itself discover the same skill through `.agents/skills/git-nest/SKILL.md`, a thin pointer back to `skills/git-nest/SKILL.md`; the product copy under `skills/` stays the single source of truth.

## License

MIT License. See [LICENSE](LICENSE).
