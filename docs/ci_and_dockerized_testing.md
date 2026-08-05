# CI And Dockerized Testing

git-nest uses GitHub Actions for continuous integration and Docker containers
to verify that its shell code works correctly across all major POSIX shells.
This document describes the CI workflows, the Docker cross-shell runner, and
how to run everything locally. For the test suites themselves, see
[`tests/tests.md`](../tests/tests.md) and
[`tests/unit-tests/unit-tests.md`](../tests/unit-tests/unit-tests.md).

## Continuous Integration (GitHub Actions)

Three manual-only workflows live under `.github/workflows/`:

| File | Runner | What it runs | Approx. time |
|------|--------|--------------|-------------|
| `ci-linux.yml` | `ubuntu-latest` | Full test suite (all integration, unit, and static-analysis tests) | ~60 min |
| `ci-macos.yml` | `macos-latest` | Unit tests + static analysis (`only 0000,0004`) | ~5 min |
| `ci-windows.yml` | `windows-latest` | Unit tests + static analysis (`only 0000,0004`) | ~10 min |

All three use the `workflow_dispatch` trigger, so they run only when started
manually -- not on every push or pull request. This keeps CI usage
deliberate and low-cost while the project is not yet public.

### Why Linux runs everything

The full suite is Linux-only because it is the platform where the whole
matrix is exercised end to end. macOS and Windows run the fast subset (unit
tests and static analysis) to catch platform-specific breakage in the core
shell code without the cost and runtime of the full suite on every OS.

### Running a workflow

1. Open the repository's **Actions** tab on GitHub.
2. Select the workflow you want to run in the left sidebar (for example
   "CI (Linux)").
3. Click **Run workflow**, pick the branch, and confirm.

Each workflow uploads `run-all-tests-results.md` and `run-all-tests.log` as a
build artifact when it finishes, so you can download the full report from the
workflow's summary page.

### Status badges

Each workflow has a status badge that can be shown in the README. The badge
reflects the most recent manual run of that workflow (it shows "no status"
until a workflow has run at least once):

```markdown
[![CI (Linux)](https://github.com/f-steff/git-nest/actions/workflows/ci-linux.yml/badge.svg)](https://github.com/f-steff/git-nest/actions/workflows/ci-linux.yml)
[![CI (macOS)](https://github.com/f-steff/git-nest/actions/workflows/ci-macos.yml/badge.svg)](https://github.com/f-steff/git-nest/actions/workflows/ci-macos.yml)
[![CI (Windows)](https://github.com/f-steff/git-nest/actions/workflows/ci-windows.yml/badge.svg)](https://github.com/f-steff/git-nest/actions/workflows/ci-windows.yml)
```

These are the standard GitHub Actions badges; they require no maintenance
beyond the workflow files themselves.

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

To broaden the macOS or Windows subset, change the `only` list, for example:

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
(`bin/git_nest.sh` + the 5 modules in `bin/lib/`). This verifies that every
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
