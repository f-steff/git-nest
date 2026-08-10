git-nest pins your multi-repo workspace as a manifest in your own
repository -- versioned like your code, restorable on any machine.

## Status

Latest release: **v{{ site.version }}**

![CI (Linux)](https://github.com/f-steff/git-nest/actions/workflows/ci-linux.yml/badge.svg)
![CI (macOS)](https://github.com/f-steff/git-nest/actions/workflows/ci-macos.yml/badge.svg)
![CI (Windows)](https://github.com/f-steff/git-nest/actions/workflows/ci-windows.yml/badge.svg)

## Quickstart

Install git-nest (latest release):

```sh
curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh
```

Windows (cmd.exe):

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex }"
```

More install options, pinned versions, and uninstall instructions are in
the [Manual](README.md#installation-and-invocation).

Then, inside any multi-repo workspace:

```sh
git-nest init
git-nest add ./libs/foo
git-nest restore
```

The full manual is on the [Manual](README.md) page.
