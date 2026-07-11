# Repository Guidelines

## Project Structure & Subproject Organization

This repository contains the behavior contract in `docs/implementation-summary.md`, the user manual in `README.md`, maintainer guidance in `docs/maintainer.md`, and a user-facing AI skill in `.agents/git-nest/SKILL.md`.

Keep implementation files organized by responsibility:

- `bin/git-nest`: main executable shell entrypoint.
- `bin/git-nest.bat`: thin polyglot launcher that works from `cmd.exe` and sh/bash contexts, then forwards to the shell script.
- `bin/git_nest.sh`: command, manifest, Git, restore, snapshot, hook, and branch-memory helpers sourced by the entrypoint.
- `tests/*.sh`: shell-based integration tests using temporary repositories.
- `docs/`: user-facing and technical documentation.
- `.agents/git-nest/SKILL.md`: portable AI skill for agents working in projects that consume git-nest.

The source of truth for behavior is `docs/implementation-summary.md`; the earlier submodule script was only a style and portability reference.

## Build, Test, and Development Commands

- `sh bin/git-nest --help`: verify command discovery and help output.
- `sh bin/git-nest init`: exercise initialization in a scratch workspace.
- `sh bin/git-nest doctor --offline`: inspect local workspace health without contacting remotes.
- `sh tests/<test-name>.sh`: run an individual integration test.
- `sh tests/run-all-tests.sh`: run the full shell test suite from Git Bash or another POSIX-like shell. The runner resets `${TMPDIR:-/tmp}/git-nest-test-workspaces` at startup and leaves generated repositories in numbered folders such as `test_01_command_restore_stale_subprojects/`.
- `tests\run-all-tests.bat`: run the same suite from `cmd.exe` through Git Bash.
- `--dry-run` is expected on `restore`, `snapshot`, `freeze`, `extract`, and `absorb` where supported by the command.

No package manager build is expected for v0.5. The tool should remain script-friendly and runnable directly from the checkout.

## Coding Style & Naming Conventions

Write portable shell where practical. Prefer POSIX-style `case`, `while`, `sed`, `awk`, `grep`, and `git` flows over Bash-only features. Avoid arrays, `mapfile`, process substitution, and associative arrays unless the need is clear and documented.

Use lowercase function names with underscores, quote variables, fail with clear error messages, and keep manifest rewrites deterministic. Keep shell implementation files in `bin/` unless the project grows enough to justify a separate library tree.

## Testing Guidelines

Tests should be integration-oriented and create local bare Git repositories as remotes under the configured `TEST_ROOT`, which defaults outside the repository. `git-nest doctor --offline` is a useful preflight before running the suite. Cover both clean paths and failure paths for `init`, `repair`, `add`, `snapshot`, `restore`, hooks, branch marks, and update/restore safety behavior, including startup from empty folders and restore with partial subproject failures.

Name tests by feature, never by development phase. Use `test_command_<command>_<behavior>.sh`, `test_command_option_<command>_<option>_<behavior>.sh`, `test_symmetry_<command_a>_<command_b>.sh`, `test_workflow_<scenario>.sh`, `test_contract_<area>.sh`, or `test_platform_<area>.sh`. Do not use `wave`, `vawe`, milestone, or implementation-phase names. Tests should print steps with what/why context, show important commands being exercised, state expected results in plain English, and describe concise results. Unexpected assertion results should include `UNEXPECTED RESULT:`. The full suite is long-running and may exceed 10 minutes; that is acceptable while stdio output continues. A test with no output for more than `TEST_WATCHDOG_SECONDS` seconds, default 180, is treated as hung and stops the suite.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects. When work is tied to a ticket, start with the ticket key. Pull requests should describe behavior changes, list tests run, and call out manifest or workflow compatibility risks. Include screenshots only for documentation or terminal-output changes where formatting matters.

## Security & Configuration Tips

Do not store provider tokens or credentials in `.gitnest`. Keep provider integration optional, and prefer `.gitnest-rc` or environment variables for local configuration. Subproject entries must pin `revision=<sha>` and must not depend only on moving branch names.
