git-nest is a lightweight shell tool that manages many independent Git repositories as one cohesive project. Built for modular codebases split across separate repos, it removes the need for submodules, subtrees, and subrepos - using only plain Git.

## Why git-nest?

Coordinating multiple Git repositories in one project usually means
submodules, subtrees, or subrepos - and each one brings a different pain
to your daily workflow.

**Submodules** leave you on a detached HEAD and silently revert local
changes with `git submodule update`. After `git clone` you must remember
`--recurse-submodules`; in CI you must configure credentials for every
private submodule. Keeping up with upstream releases means running
`git submodule update --remote` on each submodule individually - and
praying nothing breaks.

**Subtrees and subrepos** merge remote history into your own. Every
subtree pull is an upstream merge; every push back requires a subtree
split. Bisecting across subtree boundaries is painful, and the
interleaved history makes it hard to tell which change came from where.

**git-nest** takes a different approach: each subproject stays a normal,
independent Git repository with its own history, branches, and remotes.
The outer repository records only *what lives where* in `.gitnest` - a
plain-text manifest you can read, diff, and merge like any other file.

| Instead of... | git-nest |
|-|-|
| `git clone --recurse-submodules` then `git submodule update --init` | `git-nest restore` reinstates the exact workspace on any machine |
| `git submodule update --remote` per submodule (easy to forget) | `git-nest pull` fast-forwards every tracked subproject in one command unless locked |
| Pinning: commit the parent with updated `gitlink` pointers | `git-nest snapshot` records the current SHAs in `.gitnest` |
| Inspecting state: `cd` into each subproject and `git log` manually | `git-nest status`, `verify`, `outdated`, `diff` across the whole nest |

git-nest does not replace Git - it coordinates Git. You branch, commit,
review, and push in each subproject exactly as you always have. Already
using submodules, subtrees, or subrepos? `git-nest absorb` converts them
in place without losing history. To keep a subproject at a specific
revision instead of following its branch head, see
[pinning and unpinning](../howto.md#pinning-and-unpinning-subprojects).

## Quickstart

Install git-nest (latest release):

```sh
curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
```

Windows (cmd.exe) -- requires **Git for Windows** (git-nest runs on Git
Bash; every command fails with "Git is not installed or not on PATH."
when it is missing):

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex }"
```

Or directly from PowerShell 5.1+ (or pwsh):

```powershell
iex (iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1)
```

More install options, pinned versions, and uninstall instructions are in
the [Manual](../../README.md#installation-and-invocation).

Then, inside any multi-repo workspace:

```sh
git-nest init
git-nest add ./libs/foo
git-nest restore
```

git-nest records exactly which repository belongs at which path and
revision in the `.gitnest` manifest, and `git-nest restore` rebuilds that
exact workspace on any machine -- no submodules, no monorepo.
