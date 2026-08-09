<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 80" role="img" aria-label="git-nest logo">
  <style>
    .bg { fill: #2b2b2b; }
    .fg { fill: #f8f8f8; }
    @media (prefers-color-scheme: dark) {
      .bg { fill: #ececec; }
      .fg { fill: #1b1b1b; }
    }
  </style>
  <rect class="bg" width="180" height="80" rx="10"/>
  <text class="fg" x="90" y="40" text-anchor="middle" dominant-baseline="central" font-family="Consolas, Menlo, monospace" font-size="26">\\_oOO_//</text>
</svg>

git-nest pins your multi-repo workspace as a manifest in your own
repository -- versioned like your code, restorable on any machine.

## Status

![CI (Linux fast)](https://github.com/f-steff/git-nest/actions/workflows/ci-linux-fast.yml/badge.svg)
![CI (Linux)](https://github.com/f-steff/git-nest/actions/workflows/ci-linux.yml/badge.svg)
![CI (macOS fast)](https://github.com/f-steff/git-nest/actions/workflows/ci-macos-fast.yml/badge.svg)
![CI (macOS)](https://github.com/f-steff/git-nest/actions/workflows/ci-macos.yml/badge.svg)
![CI (Windows fast)](https://github.com/f-steff/git-nest/actions/workflows/ci-windows-fast.yml/badge.svg)
![CI (Windows)](https://github.com/f-steff/git-nest/actions/workflows/ci-windows.yml/badge.svg)

## Quickstart

Install git-nest (latest release):

```sh
curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/install.sh | sh
```

Windows (cmd.exe):

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/install.ps1 | iex }"
```

Then, inside any multi-repo workspace:

```sh
git-nest init
git-nest add ./libs/foo
git-nest restore
```

The full manual is on the [Manual](README.md) page.
