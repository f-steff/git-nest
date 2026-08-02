# Dockerized Cross-Shell Testing

git-nest uses Docker containers to verify that its shell code works correctly
across all major POSIX shells. This document describes how to run the tests
and what each container provides.

## Quick Start

```sh
# Run on Alpine (8 shells: dash, bash, ash, zsh, mksh, yash, fish, pwsh)
sh tests/docker/run-cross-shell-tests.sh --alpine

# Run on Debian (7 shells: dash, bash, zsh, ksh, mksh, posh, pwsh)
sh tests/docker/run-cross-shell-tests.sh --debian

# Run both (covers all 10 shells)
sh tests/docker/run-cross-shell-tests.sh
```

## Container Images

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

## What Gets Tested

### Syntax check (7 source files + 1 pwsh, 44 shell variants)

Each POSIX shell runs `sh -n` on all 7 implementation files. This verifies that
every script is syntactically valid for that shell's parser.

PowerShell 7+ (`pwsh`) is not a POSIX shell, so instead it runs a
syntax check on `bin/git-nest.ps1` itself via `pwsh -noprofile` and a
`__complete` dispatch test through the `.ps1` launcher.

Fish is also not a POSIX shell; it runs `fish --no-execute` on the
generated fish completion script rather than on implementation files.

### __complete engine test

Each POSIX shell also runs the `__complete` internal command via
`git-nest __complete 0 -- ""` and verifies the TSV output contains
command entries. This ensures the engine produces correct output
under every shell's parser regardless of syntax quirks.

### Unit tests (pure function tests)

Tests that have no external dependencies (no `git`, no filesystem state) run
through each shell to verify correct execution.

Known quirk: zsh on Alpine does not always find the `cksum` binary, which
causes `manifest_varname` (unit-test_1510) to fail. This is an Alpine zsh
environment issue, not a code portability problem.

## How It Works

The runner script `tests/docker/run-cross-shell-tests.sh`:

1. Resolves the repository root to mount as `/mnt` inside the container
2. Builds an install command for the target image's package manager
3. Runs `docker run` with the repo mounted read-only
4. Inside the container: installs packages, runs syntax checks and unit tests
5. Reports per-shell pass/fail and exits with the aggregate result

## Adding a New Shell

To test against a shell not yet in the matrix:

1. Find a Docker image or distro that packages it
2. Add the shell name to the test loop in `run-cross-shell-tests.sh`
3. Add the install command for the new distro
4. Run `sh run-cross-shell-tests.sh --<distro>` to verify

## Windows Notes

On Windows with Git Bash, the `MSYS2_ARG_CONV_EXCL=*` environment variable
prevents Git Bash from mangling Docker volume mount paths. This is set
automatically by the runner script.

## Reproducibility

These tests are fully reproducible: running the same command on the same
image produces the same result every time. No Dockerfiles to maintain -- the
runner script specifies all dependencies explicitly.
