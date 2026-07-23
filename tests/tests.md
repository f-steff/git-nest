# git-nest Test Guide

This document describes how the test suite works and how to write new tests.

## Test Philosophy

git-nest uses **integration tests**, not unit tests. Every test creates real bare Git repositories as remotes, runs `git-nest` commands against a scratch workspace, and asserts on exit codes, file contents, and output text. This means the tests are slower than unit tests but catch real integration bugs: manifest corruption, filesystem boundary violations, Git interaction errors, and shell portability issues.

There are no unit test frameworks, no mocking, and no dependency injection. The test runner is a plain POSIX shell script.

## Test Organization

Each test is a single file under `tests/` named:

```
test_<NNNN>_<category>_<behavior>.sh
```

where `<NNNN>` is a globally unique four-digit ID. IDs are allocated in blocks of 10 within categories:

| Block | Category | Description |
|-------|----------|-------------|
| 0010-0999 | `command_*` | One command per test, or one option per test |
| 2000-2999 | `contract_*` | Behavioral invariants, safety rules, schema |
| 3000-3999 | `platform_*` | Portability, shell compatibility, invocation |
| 4000-4999 | `symmetry_*` | Round-trip tests (absorb+inline, mv+remove) |
| 5000-5999 | `workflow_*` | Multi-command end-to-end scenarios |

Each test file has a `# Test: <one-line description>` header on its second line. The runner's `list` command displays these descriptions:

```sh
sh tests/run-all-tests.sh list
```

## Running Tests

### Full suite

```sh
sh tests/run-all-tests.sh          # from Git Bash or POSIX shell
tests\run-all-tests.bat            # from Windows cmd.exe
```

The full suite can take 57+ minutes on Windows. The runner clears `${TMPDIR:-/tmp}/git-nest-test-workspaces`, creates numbered workspace directories per test, writes `run-all-tests-results.md`, and captures the full run to `run-all-tests.log`.

### Selecting tests

```sh
sh tests/run-all-tests.sh list                        # list every test as ID + description
sh tests/run-all-tests.sh only 0130,5010              # run only tests 0130 and 5010
sh tests/run-all-tests.sh except 5000,5010            # run all except 5000 and 5010
sh tests/run-all-tests.sh help                        # show commands and examples
```

### Options

| Flag | Meaning |
|------|---------|
| `--verbose` / `-v` | Stream full raw output with `set -x` trace instead of curated narrative |
| `--stop-on-fail` | Stop at the first test failure |
| `--no-log` | Skip writing `run-all-tests.log` |
| `--log FILE` | Write full run log to `FILE` instead of the default |

### Running a single test directly

```sh
sh tests/test_0080_command_survey_unmanaged.sh
```

Standalone runs use a fallback narrative stream (stdout if fd 9 is not available).

## Test Output

By default the console shows a **curated narrative** per test:

```
Step N: <description>
Why: <explanation>
RUN: git-nest <command>
    <command output>
    [exit N]
OK: <result description> Output captured in <file>.
```

Each `git-nest` invocation is logged with its full output indented. The raw output of every command is also saved per test and printed only when the test fails.

Under `--verbose` / `-v`, the full raw output is streamed with a `set -x` shell trace instead. Assertions still work correctly under verbose mode because the shim's stdout/stderr delivery is unaffected by the trace on stderr.

## Writing A New Test

### Boilerplate

```sh
#!/bin/sh
# Test: <one-line description used by `list` command>

set -eu
. "$(dirname "$0")/helper.sh"
test_begin <short_name>
```

### Workspace

Allocate a numbered workspace directory that the runner cleans up:

```sh
root=$(test_workspace <unique_name>)
```

This creates `$TEST_ROOT/test_<NNNN>_<unique_name>/` and echoes the path. Always work inside this directory.

### Setup helpers

```sh
make_repo <dir>              # create a regular Git repo with identity config
make_bare_remote <dir> <work> # create a bare remote seeded with one commit
git_config                   # set git-nest-test identity in the current repo
```

### The `$GIT_NEST` shim

Use `$GIT_NEST` instead of `git-nest` directly. The shim in `tests/helper.sh` installs a wrapper that logs every invocation, its output, and its exit code to the narrative stream without affecting assertions.

```sh
"$GIT_NEST" init
"$GIT_NEST" add <url> <path>
```

### Assertion helpers

```sh
# Run a command and assert it exits 0
run_ok "description" -- <command> [args...]

# Run a command and assert it exits with a specific code (or any nonzero with `any`)
run_fail "description" <expected_code> -- <command> [args...]

# Run a command, capturing stdout and stderr to files
run_capture "description" <stdout_file> <stderr_file> -- <command> [args...]

# Assert that a file contains or does not contain literal text
assert_file_contains <file> <text>
assert_file_not_contains <file> <text>

# Assert an exact exit code without description
assert_exit_code <expected> -- <command> [args...]
```

### Test step narration

```sh
test_step "Short description" "Why this step matters and what it verifies."
```

The step description and "why" text are printed to the narrative stream. Keep the description short and the "why" specific.

```sh
describe_result "Summary of what was tested and whether it passed."
```

### Conventions

- Always use `run_ok`/`run_fail`/`run_capture` over bare command execution when testing git-nest behavior.
- Always use `assert_file_contains`/`assert_file_not_contains` for assertions on captured output.
- Every assertion that fails unexpectedly must include `UNEXPECTED RESULT:` in its error message so it stands out in logs.
- Prefer `run_capture` and separate file assertions over checking exit codes alone -- the output tells you *why* something failed.
- Prefer `run_fail` with explicit expected exit codes over `any`. Use `any` only when the exact code varies across systems and the only thing that matters is failure.

## How The Logging Shim Works

`tests/helper.sh` creates a temporary `git-nest` shim script at `$GIT_NEST_SHIM_DIR/git-nest`:

1. It prints the command and its arguments to the narrative stream (fd 9).
2. It runs the real `bin/git-nest`, capturing stdout and stderr to temp files.
3. It prints the captured output (indented) to the narrative stream, then the exit code.
4. It echoes the captured stdout and stderr to the real stdout/stderr.
5. It exits with the real exit code.

This means assertions see the real output while the narrative gets a copy. The shim is automatically installed on `PATH` via `$GIT_NEST_SHIM_DIR`.

The command log is also written to `$GIT_NEST_COMMAND_LOG` for full-suite auditability.

## Debugging A Failing Test

1. **Run the test in isolation:**
   ```sh
   sh tests/run-all-tests.sh only <ID>
   ```

2. **Run the test with verbose output:**
   ```sh
   sh tests/test_<NNNN>_<name>.sh
   ```
   (Standalone runs print to stdout directly.)

3. **Inspect the workspace:**
   The runner leaves numbered workspaces in `$TEST_ROOT`. The output log for each test is at `$TEST_ROOT/.run-all-<NNNN>.out`.

4. **Check the full run log:**
   `run-all-tests.log` contains the complete output of every command in the suite.

5. **Common failure patterns:**
   - `UNEXPECTED RESULT:` in the output → an assertion failed.
   - Test hangs with no output → the watchdog (default 180s) kills it and reports the hang.
   - `Error: not inside a git-nest workspace` → the test forgot to `cd` into its workspace.
   - `fatal: not a git repository` → a command ran outside the test's repo.

## Test ID Allocation

When adding a new test:

1. Pick the category block that matches the test's purpose:
   - Command: `0010-0999` (step by 10)
   - Contract: `2000-2999` (step by 10)
   - Platform: `3000-3999` (step by 10)
   - Symmetry: `4000-4999` (step by 10)
   - Workflow: `5000-5999` (step by 10)

2. Find the highest existing ID in that block and add 10.

3. Name the file `test_<NNNN>_<category>_<behavior>.sh` where:
   - Command tests: `test_<NNNN>_command_<command>_<behavior>.sh`
   - Contract tests: `test_<NNNN>_contract_<area>.sh`
   - Platform tests: `test_<NNNN>_platform_<area>.sh`
   - Symmetry tests: `test_<NNNN>_symmetry_<command_a>_<command_b>.sh`
   - Workflow tests: `test_<NNNN>_workflow_<scenario>.sh`

4. Add `# Test: <one-line description>` on the second line of the file.

5. Run `sh tests/run-all-tests.sh list` to verify the new test appears.
