# Maintainer Guide

This guide is for changing `git-nest` itself. For user-facing behavior, treat `docs/implementation-summary.md` as the behavior contract and `README.md` as the manual.

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

## Change Workflow

For behavior changes:

1. Read `docs/implementation-summary.md`.
2. Inspect the relevant command implementation in `bin/git_nest.sh`.
3. Add or update focused integration tests under `tests/`.
4. Update `README.md`, `docs/implementation-summary.md`, `docs/technical_docs.md`, and `.agents/git-nest/SKILL.md` when user-facing behavior changes.
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

Tests should create local bare Git repositories as remotes under `TEST_ROOT`, identify themselves through `test_begin` for standalone runs, and leave numbered workspaces for inspection. The default `TEST_ROOT` is outside the repository so startup tests are not affected by the tool repository's own Git root. The suite owns formatted headings and the final status/time summary table.

Name tests by feature, not development phase. Use only `test_command_<command>_<behavior>.sh`, `test_command_option_<command>_<option>_<behavior>.sh`, `test_symmetry_<command_a>_<command_b>.sh`, `test_workflow_<scenario>.sh`, `test_contract_<area>.sh`, or `test_platform_<area>.sh`. Do not add milestone names such as `wave`, `vawe`, or phase labels. Prefer command-specific tests first, symmetry tests second, and workflow tests only when the scenario genuinely depends on several commands.

Tests should narrate important behavior with `test_step`, `run_ok`, `run_fail`, `run_capture`, and `describe_result` from `tests/helper.sh`. The output should explain what is being tested, why the command matters, which command is being run, the expected result in plain English, and the concise result. Keep full command output captured unless a short excerpt is useful or a command fails. Unexpected assertion results should include `UNEXPECTED RESULT:` so they stand out in console output and captured logs.

The full suite is long-running and may exceed 10 minutes on Windows. That is acceptable while stdio output continues. The runner streams test output while also capturing it to per-test logs, records total suite time in `test-result.md`, and fails any active test that produces no output for more than `TEST_WATCHDOG_SECONDS` seconds. The default watchdog is 180 seconds, and the suite stops after the first hung test. Keep individual tests chatty enough that a healthy long operation emits progress before the watchdog threshold.

Cover both successful behavior and negative paths. New parser branches, missing refs, dirty or unreproducible protections, manifest state transitions, Git-style invocation, portability paths, and recursive nested-project behavior should have tests when touched.

## Scope Guardrails

`git-nest` should stay a small, predictable Git orchestration tool. Do not chase full Android `repo` parity. Prefer explicit behavior, clear failure messages, and testable shell code.

New commands must have `--json` support and integrate with the shared exit-code table. New flags on existing commands must not change default behaviour.
