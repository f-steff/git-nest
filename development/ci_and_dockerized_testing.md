# CI And Dockerized Testing

git-nest uses GitHub Actions for continuous integration and Docker containers
to verify that its shell code works correctly across all major POSIX shells.
This document describes the CI workflows, the Docker cross-shell runner, and
how to run everything locally. For the test suites themselves, see
[`tests/tests.md`](../tests/tests.md) and
[`tests/unit-tests/unit-tests.md`](../tests/unit-tests/unit-tests.md).
For the differences between local and CI environments (and the lessons
learned from CI-only failures), see
[`local-vs-ci-testing.md`](local-vs-ci-testing.md).

## Continuous Integration (GitHub Actions)

Six workflows live under `.github/workflows/`, two per target: a **fast**
one and a **full** one. The fast workflows run the same platform-focused
set on every target; the full workflows run the whole suite. The full
workflows also run on every pull request (they gate merges to `main`);
on a merge to `main`, the full Linux workflow plus the fast macOS and
Windows workflows run, and the Pages and Release workflows fire (see
`release-process.md` for the trigger matrix).

| File | Runner | What it runs | Approx. time |
|------|--------|--------------|-------------|
| `ci-linux-fast.yml` | `ubuntu-latest` | Platform-focused set (`only 0000,0004,0100,2090,3000,3010,3020,3030`) | ~1 min |
| `ci-linux.yml` | `ubuntu-latest` | Full test suite | ~2.5 min |
| `ci-macos-fast.yml` | `macos-latest` | Platform-focused set (`only 0000,0004,0100,2090,3000,3010,3020,3030`) | ~1.5 min |
| `ci-macos.yml` | `macos-latest` | Full test suite | ~6 min |
| `ci-windows-fast.yml` | `windows-latest` | Platform-focused set (`only 0000,0004,0100,2090,3000,3010,3020,3030`) | ~4 min |
| `ci-windows.yml` | `windows-latest` | Full test suite | ~40 min |

Timings are from measured runs on GitHub-hosted runners (2026-08).

### Why the fast set is platform-focused

Windows process startup is roughly an order of magnitude slower than Linux
(~40 ms per spawned process versus ~1 ms), and every git-nest command spawns
many Git and shell processes. The full suite therefore takes ~40 minutes on
Windows but only ~2.5 minutes on Linux, even though it runs the identical
commands. Running the whole suite on Windows and macOS mostly re-verifies
behavior that Linux already covers, at 10-20x the cost.

The fast workflows therefore run the set of tests that can genuinely differ
per platform:

- `0000` unit tests and `0004` static analysis -- the core, run everywhere.
- `3000` busybox compatibility, `3010` completion generation, `3020` git
  invocation, and `3030` launcher smoke tests -- the platform tests, covering
  the `.bat`/`.ps1` launchers and shell-specific completions.
- `0100` export formats -- tar/zip/Python availability differs per platform.
- `2090` paths with spaces -- explicitly Windows-relevant path handling.

The full workflows exist for pre-release verification and run the entire
suite on all three targets when you choose to run them.

### Measured Windows startup overhead

The ~19x gap is process startup, not git-nest behavior. Measured on
GitHub-hosted runners (2026-08) running the identical full suite:

| Metric | Linux | macOS | Windows |
|--------|-------|-------|---------|
| Full suite wall time | ~2.5 min | ~6 min | ~40 min |
| git-nest invocations | 550 | - | 548 |
| Average per invocation | 0.21 s | - | 4.07 s |
| Slowest invocation | ~3 s | - | ~43 s |

A direct micro-benchmark on a Windows machine: 100 invocations of
`git --version` (each spawning one native git.exe) take about 4 seconds,
versus well under a second on Linux. Because the full suite issues several
hundred git-nest commands, each spawning many git processes, the overhead
accumulates. This is inherent to Windows process creation and the MSYS2
translation layer; it is not something the test suite can optimize away.
Prefer the fast workflows on Windows and macOS for routine checks; the
full suites run on every pull request and gate merges to `main`.

### Running a workflow

1. Open the repository's **Actions** tab on GitHub.
2. Select the workflow you want to run in the left sidebar (for example
   "CI (Linux fast)").
3. Click **Run workflow**, pick the branch, and confirm.

Each workflow uploads `run-all-tests-results.md` and `run-all-tests.log` as a
build artifact when it finishes, so you can download the full report from the
workflow's summary page.

### Status badges

Each workflow has a status badge. The badges are shown on the **GitHub
Pages start page** (`https://f-steff.github.io/git-nest/`), not in the
README: the README is cloned and re-hosted, so badge URLs pointing at this
repository would show this repository's status to people viewing forks or
clones of it. The Pages site is the official release surface, so the
badges show the default-branch (main) state.

A badge reflects the most recent run of its workflow on the default branch
(it shows "no status" until a workflow has run at least once). The badge
URLs are the standard GitHub Actions form:

```
https://github.com/f-steff/git-nest/actions/workflows/ci-<target>-<fast|full>.yml/badge.svg
```

For a specific branch or event, GitHub's badge endpoint accepts `?branch=`
and `?event=` query parameters, for example:

```
https://github.com/f-steff/git-nest/actions/workflows/ci-linux.yml/badge.svg?branch=dev
```

These require the URL to name the branch explicitly; they are only useful
on external pages, not in the README (which cannot vary per branch).
Note that badge URLs return 404 while the repository is private.

### Changing what runs

To add a push or pull-request trigger, add the corresponding `on:` key to a
workflow, for example:

```yaml
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
```

To broaden a fast-workflow subset, change the `only` list, for example:

```sh
sh tests/run-all-tests.sh only 0000,0004,2000,2010,2040,2060,2070,2080,3000,3010,3020,3030
```

See [`tests/tests.md`](../tests/tests.md) for the full test ID reference and
the `only` / `except` runner commands.

## Dockerized Cross-Shell Testing

git-nest uses Docker containers to verify that its shell code works correctly
across all major POSIX shells. The runner
`tests/docker/run-cross-shell-tests.sh` mounts the repository read-only into
a container, installs the target shells, and runs the checks through each one.

### Quick start

```sh
# Run on Alpine (8 shells: dash, bash, ash, zsh, mksh, yash, fish, pwsh)
sh tests/docker/run-cross-shell-tests.sh --alpine

# Run on Debian (7 shells: dash, bash, zsh, ksh, mksh, posh, pwsh)
sh tests/docker/run-cross-shell-tests.sh --debian

# Run both (covers all 10 shells)
sh tests/docker/run-cross-shell-tests.sh
```

### Container images

| Image | Shells | Tools provided |
|-------|--------|----------------|
| `alpine:3.21` | dash, bash, ash, zsh, mksh, yash, fish, pwsh | git, tar, python3, gawk, coreutils |
| `debian:bookworm-slim` | dash, bash, zsh, ksh, mksh, posh, pwsh | git, tar, python3, gawk, shellcheck |

Combined they cover all 10 target shells:

| Shell | Role | Available in |
|-------|------|-------------|
| dash | Strict POSIX (`/bin/sh` on Debian) | Alpine + Debian |
| bash | Most common shell | Alpine + Debian |
| ash (busybox) | Embedded/Linux (`/bin/sh` on Alpine) | Alpine |
| zsh | Modern shell (macOS default) | Alpine + Debian |
| ksh | Korn shell (legacy enterprise) | Debian |
| mksh | MirBSD ksh (portable variant) | Alpine + Debian |
| yash | Yet another shell (strict POSIX) | Alpine |
| fish | Friendly interactive shell | Alpine |
| posh | Policy-compliant shell | Debian |
| pwsh | PowerShell 7+ (launcher + __complete dispatch) | Alpine + Debian |

### What gets tested

#### Syntax check (6 source files + 1 pwsh)

Each POSIX shell runs `sh -n` on the 6 implementation files
(`bin/git-nest-main.sh` + the 5 modules in `bin/lib/`). This verifies that every
script is syntactically valid for that shell's parser.

PowerShell 7+ (`pwsh`) is not a POSIX shell, so instead it runs a
syntax check on `bin/git-nest.ps1` itself via `pwsh -noprofile` and a
`__complete` dispatch test through the `.ps1` launcher.

Fish is also not a POSIX shell; it runs `fish --no-execute` on the
generated fish completion script rather than on implementation files.

#### __complete engine test

Each POSIX shell also runs the `__complete` internal command via
`git-nest __complete 0 -- ""` and verifies the TSV output contains
command entries. This ensures the engine produces correct output
under every shell's parser regardless of syntax quirks.

#### Unit tests

All unit tests in `tests/unit-tests/` (using the mock Git shim) run
through each POSIX shell to verify correct execution. zsh is skipped for
unit tests in the containers because of zsh function-resolution issues in
that environment; its syntax checks and `__complete` engine test still run.

### How it works

```
tests/docker/run-cross-shell-tests.sh
  |  resolves the repository root and mounts it read-only
  v
docker run --rm -v <repo>:/mnt:ro <image>
  |  installs packages (apk/apt) for the target shells
  |  copies the repo to /work (writable, for zsh)
  v
for each shell in the image's list:
  |-- sh -n on 6 implementation files       (POSIX shells)
  |-- unit-test_*.sh through the shell      (zsh skipped)
  |-- git-nest __complete 0 -- "" output    (engine test)
  |-- fish: fish --no-execute on the generated script
  +-- pwsh: -noprofile syntax check + __complete dispatch via git-nest.ps1
  v
per-shell PASS/FAIL table -> container pass/fail -> overall exit code
```

The runner script `tests/docker/run-cross-shell-tests.sh`:

1. Resolves the repository root to mount as `/mnt` inside the container
2. Builds an install command for the target image's package manager
3. Runs `docker run` with the repo mounted read-only
4. Inside the container: installs packages, runs syntax checks, unit tests,
   and the `__complete` engine test per shell
5. Reports per-shell pass/fail and exits with the aggregate result

### Adding a new shell

To test against a shell not yet in the matrix:

1. Find a Docker image or distro that packages it
2. Add the shell name to the test loop in `run-cross-shell-tests.sh`
3. Add the install command for the new distro
4. Run `sh tests/docker/run-cross-shell-tests.sh --<distro>` to verify

### Windows notes

On Windows with Git Bash, the `MSYS2_ARG_CONV_EXCL=*` environment variable
prevents Git Bash from mangling Docker volume mount paths. This is set
automatically by the runner script.

### Reproducibility

These tests are fully reproducible: running the same command on the same
image produces the same result every time. No Dockerfiles to maintain -- the
runner script specifies all dependencies explicitly.

## Running Locally

The same commands run locally on any POSIX-like shell:

| OS | Command |
|----|---------|
| Linux / macOS / Windows (Git Bash) | `sh tests/run-all-tests.sh` |
| Windows (cmd.exe) | `tests\run-all-tests.bat` |
| Fast subset (unit + static analysis) | `sh tests/run-all-tests.sh only 0000,0004` |
| Cross-shell Docker matrix | `sh tests/docker/run-cross-shell-tests.sh` |

### Local timing

Timings depend on the machine. As a rough guide, measured on a developer
laptop (2026-08): the fast subset takes about a minute, and the full suite
takes roughly 45 minutes on Windows (Git Bash) and 5-10 minutes on Linux or
macOS. The CI times in the workflow table above are the best reference since
they come from consistent, dedicated runners.
