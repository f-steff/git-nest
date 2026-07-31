# Maintainer Guide

This guide is for changing `git-nest` itself. For user-facing behavior, treat `docs/command-behavior-contract.md` as the behavior contract and `README.md` as the manual.

## Maintenance Rules

- Keep `GIT_NEST_VERSION` aligned with `README.md`, `version.md`, and release tests.
- Keep business logic in `bin/git_nest.sh`; keep `bin/git-nest` and `bin/git-nest.bat` thin.
- Preserve the polyglot behavior of `bin/git-nest.bat` so one IDE build-hook command can work across Windows, Linux, and macOS.
- Write portable `sh` where practical. Prefer `case`, `while`, `sed`, `awk`, `grep`, and `git`.
- Avoid arrays, `mapfile`, process substitution, associative arrays, and Bash-only conveniences unless clearly justified.
- Quote variables and validate required values before Git operations or manifest writes.
- Use `Error:`, `Warning:`, and `Notice:` for user-facing diagnostics.
- Keep manifest rewrites deterministic and readable.
- Do not add mandatory provider integration or automatic PR creation.
- Keep hooks opt-in; hooks may run `git-nest snapshot --quiet` or reproducibility checks but must not push automatically.
- **Keep all files plain ASCII** (code and documentation alike). No em/en dashes, curly quotes, arrows, box-drawing characters, or other non-ASCII punctuation. Use `--` for em-dash, `-` for en-dash, `->` for arrows, and plain `-`/`=` characters for divider lines. Straight quotes only (`'` and `"`), never curly (`'` `'` `"` `"`). This keeps diffs clean across editors/terminals with inconsistent Unicode rendering and avoids encoding surprises on Windows. This is enforced automatically: `check_ascii` in `tests/check.sh`, run as a step of `tests/test_0000_static_code_analysis.sh`, fails the suite on any non-ASCII character under `bin`, `tests`, `docs`, `skills`, or root-level `*.md` files. To check manually: `grep -rPn "[^\x00-\x7F]" bin tests docs skills *.md` (should return nothing). This does not affect the optional ANSI color escapes in `--help` output (`help_setup_colors`): those are plain ASCII bytes (ESC + digits/letters), already gated to TTY-only output and disabled by `NO_COLOR`/`GIT_NEST_NO_COLOR`/`TERM=dumb`, so they are unrelated to this rule.

## Change Workflow

For behavior changes:

1. Read `docs/command-behavior-contract.md`.
2. Inspect the relevant command implementation in `bin/git_nest.sh`.
3. Add or update focused integration tests under `tests/`.
4. Update `README.md`, `docs/command-behavior-contract.md`, `docs/technical_docs.md`, and `skills/git-nest/SKILL.md` when user-facing behavior changes. `skills/git-nest/SKILL.md` is the single source of truth for the usage skill; `.agents/skills/git-nest/SKILL.md` is only a pointer to it, so never edit workflow guidance there.
5. Every minor and patch release must include a README pass and a version-string audit. Any command name, flag, or example in the docs that does not match the code is a release blocker.
5. Run the full suite:

```bat
tests\run-all-tests.bat
```

On POSIX-like systems:

```sh
sh tests/run-all-tests.sh
```

## Testing Expectations

The project has two test suites. **Integration tests** (`tests/`) verify that commands work end-to-end by creating real Git repositories. **Unit tests** (`unit-tests/`) verify individual functions in isolation using a mock Git shim. See `tests/tests.md` and `unit-tests/unit-tests.md` for the respective writing guides.

A function is considered tested if it is covered by either suite. Running `sh unit-tests/run-all-tests.sh --coverage` reports which source functions are covered by unit tests; the integration suite covers the `cmd_*` entry points and end-to-end flows. Combined target as close to 100% as practical. Functions that are deliberately not unit-tested are catalogued in `unit-tests/unit-tests.ini [untested]` with a reason; test 1990 enforces that new code must be either covered or explained.

Unit tests follow the same naming convention but use ID block 1000-1999 and live in `unit-tests/`. Every test file must have `# Coverage: <function>` headers. Use the mock shim (`unit-tests/mocks.sh`) instead of calling real Git.

Tests should create local bare Git repositories as remotes under `TEST_ROOT`, identify themselves through `test_begin` for standalone runs, and leave numbered workspaces for inspection. The default `TEST_ROOT` is outside the repository so startup tests are not affected by the tool repository's own Git root. The suite owns formatted headings and the final status/time summary table.

See `tests/tests.md` for the complete integration test writing guide (helper API, ID allocation, debugging).

See `unit-tests/unit-tests.md` for the unit test guide (pure function testing, mock Git, assertions, coverage tracking).

Name tests by feature, not development phase, and give each a globally unique four-digit ID prefix: `test_<NNNN>_<category>_<behavior>.sh`. ID blocks step by 10 so tests can be inserted: `command_*` from 0010, `contract_*` from 2000, `platform_*` from 3000, `symmetry_*` from 4000, `workflow_*` from 5000. Categories are `test_<NNNN>_command_<command>_<behavior>.sh`, `test_<NNNN>_command_option_<command>_<option>_<behavior>.sh`, `test_<NNNN>_symmetry_<command_a>_<command_b>.sh`, `test_<NNNN>_workflow_<scenario>.sh`, `test_<NNNN>_contract_<area>.sh`, or `test_<NNNN>_platform_<area>.sh`. Put a `# Test: <one-line description>` header on the second line; `run-all-tests.sh list` shows it. Do not add milestone names such as `wave`, `vawe`, or phase labels. Prefer command-specific tests first, symmetry tests second, and workflow tests only when the scenario genuinely depends on several commands.

The runner supports commands: `list` (every test as `ID  description`), `only <ids>` and `except <ids>` (comma-separated four-digit IDs), and `help`. `--stop-on-fail` stops at the first failure. An unknown command, option, or ID prints help and stops.

Tests should narrate important behavior with `test_step`, `run_ok`, `run_fail`, `run_capture`, and `describe_result` from `tests/helper.sh`. The output should explain what is being tested, why the command matters, which command is being run, the expected result in plain English, and the concise result. Keep full command output captured unless a short excerpt is useful or a command fails. Unexpected assertion results should include `UNEXPECTED RESULT:` so they stand out in console output and captured logs.

The full suite is long-running and may exceed 10 minutes on Windows. That is acceptable while stdio output continues. By default the runner streams a curated per-test narrative (step descriptions and each git-nest command with its output, produced via a logging shim on `$GIT_NEST` and fd 9); the full raw output is captured per test and printed when a test fails. Use `--verbose`/`-v` to stream the full raw output with a shell trace instead. The runner records total suite time in `run-all-tests-results.md`, captures the entire run to `run-all-tests.log` by default (disable with `--no-log`, redirect with `--log FILE`), and fails any active test that produces no output for more than `TEST_WATCHDOG_SECONDS` seconds. The default watchdog is 180 seconds, and the suite stops after the first hung test. Keep individual tests chatty enough that a healthy long operation emits progress before the watchdog threshold.

Cover both successful behavior and negative paths. New parser branches, missing refs, dirty or unreproducible protections, manifest state transitions, Git-style invocation, portability paths, and recursive nested-project behavior should have tests when touched.

## Verbose Toggle

The runner supports `--verbose`/`-v` to stream full raw output with a `set -x` shell trace instead of the default curated narrative. Tests must tolerate this: assertions using `run_ok`, `run_fail`, and `run_capture` from `tests/helper.sh` work correctly under `-x` because the shim's stdout/stderr delivery is unaffected by the trace on stderr. A test that reads its own output from fd 9 or assumes a clean stderr may break under `--verbose`. Keep all assertions on captured files or exit codes, never on stderr content.

## Multi-Step Test Structure

A test may contain multiple `test_step` calls to partition its work into visible, independently-described phases. Each step should have a clear Why statement explaining the purpose. The runner shows every step in the output automatically.

When calling a function that returns non-zero for expected conditions (e.g., a tool-check function that returns 2 for "tool not available"), wrap the call with `set +e` / `set -e` to prevent the shell from exiting due to `-e`:

```sh
set +e; check_shellcheck; sc_rc=$?; set -e
case $sc_rc in
    0) describe_result "passed" ;;
    2) describe_result "skipped (tool not available)" ;;
    *) exit 1 ;;
esac
```

Test 0000 (`test_0000_static_code_analysis.sh`) is the reference for this pattern. It runs four tool checks as separate steps, tracks skipped tools, and reports a summary. When adding new static checks, add them as additional steps in that file rather than creating separate test files, so the suite's quality gate stays in one place.

## Scope Guardrails

`git-nest` should stay a small, predictable Git orchestration tool. Do not chase full Android `repo` parity. Prefer explicit behavior, clear failure messages, and testable shell code.

New commands must have `--json` support and integrate with the shared exit-code table. New flags on existing commands must not change default behaviour.
