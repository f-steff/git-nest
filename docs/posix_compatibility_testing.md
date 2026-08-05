# POSIX Compatibility Testing

git-nest targets portable POSIX shell (`/bin/sh`). This document describes how
to verify cross-shell compatibility using the posix-shell skill.

## The posix-shell Skill

The [POSIX Shell Skill](https://github.com/f-steff/POSIX_Shell_Skill) is a
portable POSIX shell scripting skill for AI coding assistants. It provides:

- **Cross-shell test runners** -- test scripts across dash, bash, ash, zsh,
  mksh, yash, and more
- **Docker-based testing** -- run tests inside an Alpine container with
  multiple shells installed
- **Linting scripts** -- shellcheck, shfmt, checkbashisms
- **ASCII scanner** -- byte-level non-ASCII detection using `od`

### Installing the Skill

The skill is not committed inside this repository. `.agents/skills/posix-shell/SKILL.md`
is a thin pointer to the external skill repository. To make the full skill
(including its test runners) available to development agents, clone it once
from the repository root:

```sh
git clone https://github.com/f-steff/POSIX_Shell_Skill.git \
    .agents/skills/posix-shell/source
```

The installed content lives under `.agents/skills/posix-shell/source/`, is
ignored via `.gitignore`, and must not be committed; updates come from
`git -C .agents/skills/posix-shell/source pull`.

To install the skill into a new project, clone it directly into your AI tool's
skills path:

```sh
# OpenCode
git clone https://github.com/f-steff/POSIX_Shell_Skill.git ~/.config/opencode/skills/posix-shell
# Codex CLI
git clone https://github.com/f-steff/POSIX_Shell_Skill.git ~/.agents/skills/posix-shell
# Claude Code
git clone https://github.com/f-steff/POSIX_Shell_Skill.git ~/.claude/skills/posix-shell
```

The skill source is at `https://github.com/f-steff/POSIX_Shell_Skill.git`.

## Running Cross-Shell Tests

### Using the built-in test runner (local shells)

The skill provides `test_runner.sh` which runs a script through all locally
available shells. This script ships in the external skill and is present here
only after installing it (see "Installing the Skill" above):

```sh
sh .agents/skills/posix-shell/source/scripts/test_runner.sh bin/git_nest.sh
sh .agents/skills/posix-shell/source/scripts/test_runner.sh tests/unit-tests/
```

### Using Docker (all shells)

The `docker_test.sh` script runs tests inside an Alpine container with
multiple shells installed. Like `test_runner.sh`, it comes from the external
skill and requires the install step above:

```sh
sh .agents/skills/posix-shell/source/scripts/docker_test.sh \
    --verbose bin/lib/git-nest-manifest.sh
```

This mounts the target into an Alpine container and runs it through all
available shells (dash, bash, ash, zsh, mksh, yash).

## Test Results

These are snapshots from past verification runs. For current per-shell
results, run the repository's own cross-shell runner:
`sh tests/docker/run-cross-shell-tests.sh` (see
`docs/ci_and_dockerized_testing.md`).

### Syntax check (6 source files, 6 shells, 36 tests)

All 6 shell implementation files pass syntax check across the Alpine shell
set:

| File | dash | bash | ash | zsh | mksh | yash |
|------|------|------|-----|-----|------|------|
| `bin/git_nest.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-manifest.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-commands.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-conversion.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-doctor.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-hooks.sh` | PASS | PASS | PASS | PASS | PASS | PASS |

**Result: 36/36 PASS.** (`bin/git-nest.bat` is a Windows batch launcher, not
a shell implementation, and is not `sh -n`-checked.)

### Unit tests (31 tests per shell)

The full unit suite in `tests/unit-tests/` passes through every POSIX shell
in the repository's Docker runner. zsh unit tests are skipped there (zsh
function-resolution issues in the container); its syntax checks and
`__complete` engine test still run.

## Known Limitations

- **ksh and posh** are not available in the `alpine:3.21` package repository.
  Testing on these shells requires a different base image (Debian, Fedora).
- **zsh in containers** is skipped for unit tests because of zsh
  function-resolution issues in the container environment; this is an
  Alpine/zsh quirk, not a portability issue.
- **Docker on Windows** requires `MSYS2_ARG_CONV_EXCL="*"` to prevent Git Bash
  from mangling volume mount paths. The `docker_test.sh` script handles this
  automatically (scoped to the docker invocation only, never exported).

## Adding New Tests

The `docker_test.sh` commands below require the skill to be installed
(see "Installing the Skill" above). When adding shell code to git-nest:

1. Run the existing unit tests through the Docker test runner to verify
   cross-shell compatibility:
   ```sh
   sh .agents/skills/posix-shell/source/scripts/docker_test.sh tests/unit-tests/unit-test_NNNN_*.sh
   ```
2. Run the syntax check across all shells:
   ```sh
   sh .agents/skills/posix-shell/source/scripts/docker_test.sh bin/lib/your-new-script.sh
   ```
3. Fix any shell-specific issues before committing.
