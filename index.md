git-nest pins your multi-repo workspace as a manifest in your own
repository -- versioned like your code, restorable on any machine.

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
the [Manual](README.md#installation-and-invocation).

Then, inside any multi-repo workspace:

```sh
git-nest init
git-nest add ./libs/foo
git-nest restore
```

git-nest records exactly which repository belongs at which path and
revision in the `.gitnest` manifest, and `git-nest restore` rebuilds that
exact workspace on any machine -- no submodules, no monorepo.
