# Unit Test Guide

## Philosophy

Unit tests exercise individual functions in isolation. Each test loads the relevant library module from `bin/lib/`, sets up mock responses for any Git operations the function performs, and asserts the correct output or exit code.

Unlike the integration tests under `tests/`, unit tests do **not** create real Git repositories, remotes, or bare clones. They use a mock Git shim that intercepts all `git` calls and returns canned responses.

Unit tests complement integration tests. Integration tests verify command behavior end-to-end; unit tests verify that individual functions handle edge cases correctly.

## Directory structure

```
unit-tests/
|-- helper.sh          # Setup, teardown, assertion API, library loader
|-- mocks.sh           # Mock Git shim and response table
|-- run-all-tests.sh   # POSIX runner
|-- run-all-tests.bat  # Polyglot Windows launcher
|-- unit-tests.md      # This file
|-- unit-test_NNNN_<category>_<behavior>.sh
```

## Test file format

Each file has:

- A `#!/bin/sh` shebang with `set -eu`
- A `# Unit test: <description>` header on line 2 (used by the runner's `list` command)
- One or more `# Coverage: <function>` headers listing the functions tested
- Calls to `helper.sh` via `. "$(dirname "$0")/helper.sh"`
- A call to `setup_unit_test` at the start
- A call to `load_lib` for each library module needed
- Assertions using `assert_eq`, `assert_ok`, `assert_fail`

### Template

```sh
#!/bin/sh
# Unit test: <one-line description of what this tests>
# Coverage: function_name_1, function_name_2

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Test cases...

printf 'All tests passed.\n'
```

## Assertion API

`assert_eq <actual> <expected> [<description>]`
: Compare two strings. Fails the test with a diff message if they differ.

`assert_ok <description> -- <command> [args...]`
: Run a command and fail if it exits nonzero.

`assert_fail <description> -- <command> [args...]`
: Run a command and fail if it exits zero (expected error path).

## Mock system

`mocks.sh` installs a `git` shim on `PATH` during `setup_unit_test`. The shim looks up responses from a table file keyed by `subcommand<TAB>full args`. Default responses cover common operations; tests can override or extend them with `mock_git_response`.

```sh
# Override a specific response
mock_git_response "rev-parse --is-shallow-repository" "true"

# Add a new response for a multi-argument command
mock_git_response "config --get remote.origin.promisor" "false"
```

The mock Git shim returns exit code 0 for known commands and 1 for unknown ones. Its stdout is the canned response; stderr is empty.

## Coverage

Each test file lists the functions it covers in `# Coverage:` headers. The runner's `--coverage` flag collects all coverage headers, compares them against all function definitions in `bin/lib/*.sh`, and reports:

```
--- Coverage Report ---
Covered: 86/311 = 27.7%
Deliberately untested: 225
Unclassified: 0
```

Functions listed in `unit-tests.ini` under the `[untested]` section are considered
deliberately untested (see below). The report also shows any unclassified functions
that are neither covered nor listed — these are newly added code that needs attention.

Use `--no-coverage` to skip the coverage scan for faster iteration during test development.

## Deliberately Untested Functions (`unit-tests.ini`)

Functions that are not suitable for unit testing are catalogued in `unit-tests.ini`
under the `[untested]` section, each with a category and reason:

```ini
# Category codes: cmd-entrypoint, trivial, pure, stateful, filesystem,
#                 arg-diff-mock, multi-step, completion, error-sink
cmd_restore="cmd-entrypoint: test_0020, test_0200, test_0205"
repo_dirty="trivial: delegates to repo_has_dirty"
```

Every function must be either covered by a unit test OR listed in this file.
Test 1990 (`unit-test_1990_unit_coverage_check.sh`) enforces this automatically:
it scans all source files, all coverage headers, and `unit-tests.ini`, and fails
if any function is neither tested nor listed. To fix a failure, either:

1. Write a unit test and add a `# Coverage:` header matching the function name
2. Add a line to `unit-tests.ini [untested]`: `function="category: reason"`
3. Check spelling if the function is already covered but the name differs

## Runner commands

```sh
sh unit-tests/run-all-tests.sh              # Run all unit tests
sh unit-tests/run-all-tests.sh list         # List all tests as ID + description
sh unit-tests/run-all-tests.sh only 1000,1010 # Run only given IDs
sh unit-tests/run-all-tests.sh except 1020   # Run all except given ID
sh unit-tests/run-all-tests.sh help          # Print help
```

Options:
- `--verbose` (`-v`): Stream full output instead of summary
- `--stop-on-fail`: Stop at the first failing test
- `--no-coverage`: Skip the coverage report

## Integration with main test suite

From the main `tests/` directory:

```sh
sh tests/run-all-tests.sh --unit-tests       # Run unit tests instead of integration
sh tests/run-all-tests.sh --unit-tests only 1000,1010
```

## Test ID allocation

Unit tests use block 1000–1999. Within the block, sub-ranges by source module:

| Range | Category | What it covers |
|-------|----------|---------------|
| 1000–1099 | unit_manifest | `path_is_relative_safe`, `normalize_path`, `validate_clone_mode` |
| 1100–1199 | unit_path | Path safety functions |
| 1200–1299 | unit_helper | `shell_quote`, `json_escape`, `config_get` |
| 1300–1399 | unit_clone | Clone mode functions |
| 1400–1499 | unit_commands | Command helper functions |
| 1500–1999 | unit_* | Extended coverage |
