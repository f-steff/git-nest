# git-nest Test Guide

There are two test suites plus a cross-shell Docker runner, all organized
under `tests/`:

```
tests/
  run-all-tests.sh            main runner (IDs 0000-5050)
  run-all-tests.bat           cmd.exe polyglot launcher for the runner
  tests.md                    this guide (overall test strategy)
  docker/
    run-cross-shell-tests.sh  Docker cross-shell checks
  unit-tests/                 function-level suite with a mock Git shim
    run-all-tests.sh/.bat     standalone unit runner (IDs 1000-1999)
    helper.sh  mocks.sh  unit-tests.ini  unit-tests.md
    unit-test_*.sh            (31 files)
  integration-tests/          end-to-end suite with real Git repositories
    helper.sh  check.sh
    test_0000_unit_tests.sh   bridge: unit suite inside the full run
    test_0004_static_code_analysis.sh
    test_0010_...sh .. test_5050_...sh
```

- **Integration tests** (`integration-tests/`): create real Git repositories
  and run `git-nest` commands end-to-end. They verify command behavior
  against actual repositories.

- **Unit tests** (`unit-tests/`): test individual functions in isolation
  using a mock Git shim. See `unit-tests/unit-tests.md` for the unit test
  guide, the mock system, and the coverage classification
  (`unit-tests.ini`) that explains why certain functions are not
  unit-tested.

- **Cross-shell checks** (`docker/`): run syntax checks, unit tests, and the
  `__complete` engine under many shells in Alpine and Debian containers.
  See `docs/ci_and_dockerized_testing.md`.

## How The Pieces Fit Together

```
+-- tests/run-all-tests.sh          (full suite, IDs 0000-5050)
|     |
|     +-- integration-tests/test_XXXX_*.sh   (real repos, end-to-end)
|     |
|     +-- test_0000_unit_tests.sh --bridge--> unit-tests/unit-test_*.sh
|     |                                         (mock git shim)
|     |
|     +-- test_0004_static_code_analysis.sh    (quality gates)
|
+-- tests/unit-tests/run-all-tests.sh      (standalone unit runner, 1000-1999)
|
+-- tests/docker/run-cross-shell-tests.sh  (Docker: syntax + unit + __complete)
```

The main runner executes every `integration-tests/test_XXXX_*.sh` file in ID
order. `test_0000_unit_tests.sh` is the bridge that runs the unit suite
inside the full run, so `sh tests/run-all-tests.sh` covers both suites in one
pass. The unit suite can also be run standalone with
`sh tests/unit-tests/run-all-tests.sh`.

## Test Philosophy (integration)

git-nest uses integration tests. Every test creates real bare Git
repositories as remotes, runs `git-nest` commands against a scratch
workspace, and asserts on exit codes, file contents, and output text. The
test runner is a plain POSIX shell script.

(see `unit-tests/unit-tests.md` for unit test philosophy)

## How A Test Runs

```
helper.sh  ->  test_workspace  ->  make_bare_remote  ->  run git-nest
   |                |                    |                   |
   |          allocates a numbered   creates a seed repo    runs commands
   |          workspace under       and a bare remote       through the
   |          $TEST_ROOT            on main                 logging shim
   |
   +-- narrates steps (test_step), commands (print_command),
       and results (describe_result) on fd 9
```

Each test sources `helper.sh` relative to itself, so tests can be run
individually (`sh tests/integration-tests/test_0010_command_absorb_sources.sh`)
or through the runner; both paths get identical narration.

## Test Organization

Each test is a single file under `tests/integration-tests/` named:
`test_<NNNN>_<category>_<behavior>.sh`

ID blocks: 0010-0999 command, 1000-1999 unit, 2000-2999 contract,
3000-3999 platform, 4000-4999 symmetry, 5000-5999 workflow. IDs `0000`
(unit-suite bridge) and `0004` (static code analysis) are reserved
exceptions, and a `0205`-style insertion is allowed between blocks.

## Platform-Focused CI Set

The CI fast workflows (see `docs/ci_and_dockerized_testing.md`) run a fixed
subset of tests on every target:

```
only 0000,0004,0100,2090,3000,3010,3020,3030
```

This set exists because Windows process startup is roughly an order of
magnitude slower than Linux, so the full suite takes about 19x longer on
Windows (~40 min) than on Linux (~2.5 min) while re-verifying the same
behavior. The fast set keeps the tests that can genuinely differ per
platform: unit tests, static analysis, the platform tests (launchers,
completions, git invocation), export formats (tar/zip/Python availability),
and paths-with-spaces.

**When you add a new test, decide which set it belongs to and update the
workflow files and this list accordingly:**

- A test that exercises something platform-specific -- a launcher (`.bat`,
  `.ps1`), a shell completion, a tool whose availability or behavior differs
  by OS (tar, zip, Python, busybox), or path handling that differs on
  Windows -- must be added to the fast set in
  `.github/workflows/ci-*-fast.yml` (all three) and to the `only` list
  documented here and in `docs/ci_and_dockerized_testing.md`.
- A test that verifies command behavior, contracts, symmetry, or workflows
  identical across platforms belongs in the full suite only; it still runs
  on Windows and macOS via the full workflows, which are manual-only and
  intended for pre-release verification.

If you change the fast set, update all three places together: the three
`ci-*-fast.yml` workflow files, this section, and the workflow table in
`docs/ci_and_dockerized_testing.md`.

## Running Tests

```sh
sh tests/run-all-tests.sh
sh tests/run-all-tests.sh list
sh tests/run-all-tests.sh only 0130,5010
sh tests/run-all-tests.sh except 5000,5010,5020
sh tests/run-all-tests.sh cleanup
sh tests/unit-tests/run-all-tests.sh
```

Every run starts by cleaning the persistent workspace root
(`${TMPDIR:-/tmp}/git-nest-test-workspaces`) and stale temp artifacts from
previous runs, so interrupted runs never contaminate the next one. The
`cleanup` command performs only that cleanup and stops.
