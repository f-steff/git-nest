# POSIX Shell Skill -- Improvement Suggestions

Based on integrating the [POSIX Shell Skill](https://github.com/f-steff/POSIX_Shell_Skill)
into git-nest's test suite, the following improvements would make it more
useful for testing real-world shell projects.

## 1. Package Availability for Test Shells

**Issue:** The `docker_test.sh` script installs shells via `apk add` in Alpine,
but `ksh` and `posh` are not available in Alpine 3.21's package repository.
This means the cross-shell test matrix is limited.

**Suggestion:** Provide alternative base images:

- **Alpine** for: dash, bash, ash, zsh, mksh, yash
- **Debian** for: dash, bash, zsh, ksh, mksh, posh
- Combined they cover all 8 shells

The `docker_test.sh` could accept a `--base-image` flag to choose the distro,
or auto-detect available packages.

## 2. Tool Installation for Real-World Projects

**Issue:** The Docker test runner installs shells but not project-level
dependencies (git, awk, python, tar, etc.). Many real shell scripts depend on
these tools. Our test suite, for example, needs `git` and `awk` to run.

**Suggestion:** Add a `--install <packages>` flag or allow the caller to
specify an install command snippet:

```sh
sh docker_test.sh --install "git tar python3 gawk" script.sh
```

This would make the runner useful for testing projects that depend on common
POSIX tools beyond just the shell itself.

## 3. Exit Code Propagation

**Issue:** The `docker_test.sh` always exits 0 (success) even when one or
more shells fail the test. The exit code must be propagated upward for CI
pipelines to detect failures.

**Suggestion:** Accumulate the number of failing shells and exit with that
count (or exit 1 when any shell fails). Current behavior:

```sh
# All tests fail but docker_test.sh still exits 0
sh docker_test.sh mybroken.sh  # exit 0 even when all shells FAIL
```

## 4. Windows Path Handling

**Issue:** On Git Bash for Windows, `$(pwd)` returns paths like
`/c/Users/...` which Docker does not understand for volume mounts. The script
uses `cygpath -m` for conversion, but this only works in full Cygwin
environments, not in Git Bash (MSYS2).

**Suggestion:** For Git Bash (MSYS2/MINGW), use `pwd -W` to get a Windows
path, and set `MSYS2_ARG_CONV_EXCL=*` scoped to the docker invocation only:

```sh
case "$(uname -s)" in
    MINGW*|MSYS*) winpath=$(pwd -W) ;;
    *) winpath=$(pwd) ;;
esac
MSYS2_ARG_CONV_EXCL="*" docker run -v "$winpath:/mnt:ro" ...
```

Caution (learned in git-nest, 2026-07): do **not** `export
MSYS2_ARG_CONV_EXCL="*"`. Exporting it disables MSYS2 POSIX-to-Windows
argument conversion for every native binary spawned afterwards in the whole
process tree, so native `git.exe` receives raw `/tmp/...` paths and fails
with `fatal: cannot change to '/tmp/...'`. Scope the variable to the single
docker command as shown, or unset it afterwards.

## 5. Test Output Format

**Issue:** The `--quiet` mode produces compact output (`T1: dash... PASS`)
which is useful for machine consumption but hard to read. The `--verbose`
mode is better for humans.

**Suggestion:** Default to verbose output when stdout is a terminal and
quiet output when stdout is a pipe (auto-detection via `[ -t 1 ]`).

## 6. Summary of Shell Coverage Across Distros

Add a reference table to the README:

| Shell | Alpine | Debian | Fedora |
|-------|--------|--------|--------|
| dash | yes | yes | yes |
| bash | yes | yes | yes |
| ash (busybox) | built-in | no | no |
| zsh | yes | yes | yes |
| ksh | no | yes | yes |
| mksh | yes | yes | yes |
| yash | yes | no | no |
| posh | no | yes | no |

This would help users choose the right base image for their shell coverage
requirements.
