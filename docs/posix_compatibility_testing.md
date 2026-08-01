# POSIX Compatibility Testing

git-nest targets portable POSIX shell (`/bin/sh`). This document describes how
to verify cross-shell compatibility using the posix-shell skill.

## The posix-shell Skill

The [POSIX Shell Skill](https://github.com/f-steff/POSIX_Shell_Skill) is a
portable POSIX shell scripting skill for AI coding assistants. It provides:

- **Cross-shell test runners** — test scripts across dash, bash, ash, zsh,
  mksh, yash, and more
- **Docker-based testing** — run tests inside an Alpine container with
  multiple shells installed
- **Linting scripts** — shellcheck, shfmt, checkbashisms
- **ASCII scanner** — byte-level non-ASCII detection using `od`

### Installing the Skill

The skill is installed locally at `.agents/skills/posix-shell/`. It was
copied from the development repository (see the `AGENTS.md` at the root of
the [POSIX_Shell_Skill](https://github.com/f-steff/POSIX_Shell_Skill) repo
for more installation methods).

To install into a new project, copy the skill into your AI tool's skills path:

```sh
# OpenCode
cp -r skills/posix-shell ~/.config/opencode/skills/
# Codex CLI
cp -r skills/posix-shell ~/.agents/skills/
# Claude Code
cp -r skills/posix-shell ~/.claude/skills/
```

The skill source is at `https://github.com/f-steff/POSIX_Shell_Skill.git`.

## Running Cross-Shell Tests

### Using the built-in test runner (local shells)

The skill provides `test_runner.sh` which runs a script through all locally
available shells:

```sh
sh .agents/skills/posix-shell/scripts/test_runner.sh bin/git_nest.sh
sh .agents/skills/posix-shell/scripts/test_runner.sh unit-tests/
```

### Using Docker (all shells)

The `docker_test.sh` script runs tests inside an Alpine container with
multiple shells installed:

```sh
sh .agents/skills/posix-shell/scripts/docker_test.sh \
    --verbose bin/lib/git-nest-manifest.sh
```

This mounts the target into an Alpine container and runs it through all
available shells (dash, bash, ash, zsh, mksh, yash).

## Test Results

### Syntax check (7 source files, 6 shells, 42 tests)

All source files pass syntax check across all available shells:

| File | dash | bash | ash | zsh | mksh | yash |
|------|------|------|-----|-----|------|------|
| `bin/git_nest.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-manifest.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-commands.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-conversion.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-doctor.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/lib/git-nest-hooks.sh` | PASS | PASS | PASS | PASS | PASS | PASS |
| `bin/git-nest.bat` | PASS | PASS | PASS | PASS | PASS | PASS |

**Result: 42/42 PASS.**

### Pure unit tests (9 tests, 6 shells, 54 tests)

| Test | dash | bash | ash | zsh | mksh | yash |
|------|------|------|-----|-----|------|------|
| 1000 (path_is_relative_safe) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1010 (normalize_path) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1020 (validate_clone_mode) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1450 (tree_survey_typelabel) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1460 (diagnostic helpers) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1470 (sleep_ms, regex_escape) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1510 (manifest section) | PASS | PASS | PASS | FAIL* | PASS | PASS |
| 1520 (redact_stream) | PASS | PASS | PASS | PASS | PASS | PASS |
| 1640 (export format) | PASS | PASS | PASS | PASS | PASS | PASS |

**Result: 53/54 PASS** (\*1 zsh failure on Alpine due to missing `cksum` in zsh's
PATH — not a code portability issue. `cksum` is a standalone binary provided by
BusyBox; zsh on Alpine does not always find it. All other shells run it correctly.)

## Known Limitations

- **ksh and posh** are not available in the `alpine:3.21` package repository.
  Testing on these shells requires a different base image (Debian, Fedora).
- **zsh on Alpine** may fail on tests using `cksum` if the binary is not in
  zsh's PATH after installation. This is an Alpine/zsh quirk, not a portability
  issue.
- **Docker on Windows** requires `MSYS2_ARG_CONV_EXCL="*"` to prevent Git Bash
  from mangling volume mount paths. The `docker_test.sh` script handles this
  automatically.

## Adding New Tests

When adding shell code to git-nest:

1. Run the existing unit tests through the Docker test runner to verify
   cross-shell compatibility:
   ```sh
   sh .agents/skills/posix-shell/scripts/docker_test.sh unit-tests/unit-test_NNNN_*.sh
   ```
2. Run the syntax check across all shells:
   ```sh
   sh .agents/skills/posix-shell/scripts/docker_test.sh bin/lib/your-new-script.sh
   ```
3. Fix any shell-specific issues before committing.
