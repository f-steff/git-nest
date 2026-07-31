# git-nest Test Guide

There are two test suites:

- **Integration tests** (this directory): Create real Git repositories and run
  `git-nest` commands end-to-end. They verify command behavior against actual
  repositories.

- **Unit tests** (`unit-tests/`): Test individual functions in isolation using
  a mock Git shim. See `unit-tests/unit-tests.md` for the unit test guide,
  the mock system, and the coverage classification (`unit-tests.ini`) that
  explains why certain functions are not unit-tested.

Run the unit suite from the main runner:
```sh
sh tests/run-all-tests.sh --unit-tests
sh tests/run-all-tests.sh --unit-tests list
```

## Test Philosophy (integration)

git-nest uses integration tests. Every test creates real bare Git repositories as remotes, runs `git-nest` commands against a scratch workspace, and asserts on exit codes, file contents, and output text. The test runner is a plain POSIX shell script.

(see `unit-tests/unit-tests.md` for unit test philosophy)

## Test Organization

Each test is a single file under `tests/` named:
`test_<NNNN>_<category>_<behavior>.sh`

ID blocks: 0010-0999 command, 1000-1999 unit, 2000-2999 contract,
3000-3999 platform, 4000-4999 symmetry, 5000-5999 workflow.

## Running Tests

```sh
sh tests/run-all-tests.sh
sh tests/run-all-tests.sh list
sh tests/run-all-tests.sh only 0130,5010
sh tests/run-all-tests.sh --unit-tests
```
