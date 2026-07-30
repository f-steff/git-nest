# Repository Guidelines

## Project Structure & Subproject Organization

This repository contains the behavior contract in `docs/command-behavior-contract.md`, the user manual in `README.md`, maintainer guidance in `docs/maintainer.md`, and a user-facing AI skill in `skills/git-nest/SKILL.md`.

Keep implementation files organized by responsibility:

- `bin/git-nest`: main executable shell entrypoint.
- `bin/git-nest.bat`: thin polyglot launcher that works from `cmd.exe` and sh/bash contexts, then forwards to the shell script.
- `bin/git_nest.sh`: command, manifest, Git, restore, snapshot, hook, and branch-memory helpers sourced by the entrypoint.
- `tests/*.sh`: shell-based integration tests using temporary repositories.
- `docs/`: user-facing and technical documentation.
- `skills/git-nest/SKILL.md`: portable AI usage skill shipped to projects that consume git-nest. This is the single source of truth for that skill.
- `.agents/skills/<name>/SKILL.md`: skill tree discovered by development agents (opencode, Codex, Claude Code) working on git-nest itself.

The source of truth for behavior is `docs/command-behavior-contract.md`; the earlier submodule script was only a style and portability reference.

## AI Skills And Agent Bootstrap

Development agents bootstrap from this `AGENTS.md` at the repository root. Both Codex and opencode read it, and opencode also loads global rules from `~/.config/opencode/AGENTS.md`.

There are two distinct skill trees. Do not conflate them:

- `skills/` holds product skills shipped to consumers of git-nest. `skills/git-nest/SKILL.md` is the single source of truth for the git-nest usage skill.
- `.agents/skills/` holds the skill tree that development agents discover while working on git-nest. opencode only discovers skills at `.agents/skills/<name>/SKILL.md` (and `.opencode/skills/`, `.claude/skills/`), never at `.agents/<name>/SKILL.md`.

To keep one source of truth without duplicating skill bodies, `.agents/skills/git-nest/SKILL.md` is a thin pointer that redirects agents to `skills/git-nest/SKILL.md`. Development-only skills that never ship, such as `windows-powershell-shell`, live only under `.agents/skills/` and are authoritative there.

When you change the usage skill, edit `skills/git-nest/SKILL.md`. If you change its purpose, keep the pointer's `description` frontmatter matching the source. `tests/test_contract_skills_pointer.sh` enforces this layout.

## Build, Test, and Development Commands

- `sh bin/git-nest --help`: verify command discovery and help output.
- `sh bin/git-nest init`: exercise initialization in a scratch workspace.
- `sh bin/git-nest doctor --offline`: inspect local workspace health without contacting remotes.
- `sh tests/<test-name>.sh`: run an individual integration test.
- `sh tests/run-all-tests.sh`: run the full shell test suite from Git Bash or another POSIX-like shell. The runner resets `${TMPDIR:-/tmp}/git-nest-test-workspaces` at startup and leaves generated repositories in numbered folders. It writes the Markdown summary `run-all-tests-results.md` and captures the full run to `run-all-tests.log` by default; pass `--no-log` to skip the log or `--log FILE` to redirect it. The console shows a curated per-test narrative (step descriptions and each git-nest command with its output); the full raw output is saved per test and printed when a test fails. Pass `--verbose` (`-v`) to stream everything with a shell trace instead, or `--stop-on-fail` to stop at the first failure. The summary table sizes its columns to the longest test name.
- `sh tests/run-all-tests.sh list`: list every test as `ID  description`. `sh tests/run-all-tests.sh only 0130,5010` runs only those test IDs; `except 5000,5010` runs all but those; `help` prints the commands. An unknown command, option, or test ID prints help and stops.
- `tests\run-all-tests.bat`: run the same suite from `cmd.exe` through Git Bash. It forwards all commands and options (`list`, `only`, `except`, `help`, `--verbose`, `--stop-on-fail`, `--no-log`, `--log FILE`) to the shell runner.
- `--dry-run` is expected on `restore`, `snapshot`, `freeze`, `extract`, and `absorb` where supported by the command.

No package manager build is expected for v0.5. The tool should remain script-friendly and runnable directly from the checkout.

## Coding Style & Naming Conventions

Write portable shell where practical. Prefer POSIX-style `case`, `while`, `sed`, `awk`, `grep`, and `git` flows over Bash-only features. Avoid arrays, `mapfile`, process substitution, and associative arrays unless the need is clear and documented.

Use lowercase function names with underscores, quote variables, fail with clear error messages, and keep manifest rewrites deterministic. Keep shell implementation files in `bin/` unless the project grows enough to justify a separate library tree.

## Testing Guidelines

Tests should be integration-oriented and create local bare Git repositories as remotes under the configured `TEST_ROOT`, which defaults outside the repository. `git-nest doctor --offline` is a useful preflight before running the suite. Cover both clean paths and failure paths for `init`, `tidy`, `add`, `snapshot`, `restore`, hooks, branch marks, and update/restore safety behavior, including startup from empty folders and restore with partial subproject failures.

Name tests by feature, never by development phase, and give each a globally unique four-digit ID prefix so the runner can list and select them. Files are named `test_<NNNN>_<category>_<behavior>.sh`, where the ID blocks are: `command_*` from 0010, `contract_*` from 2000, `platform_*` from 3000, `symmetry_*` from 4000, and `workflow_*` from 5000, each stepping by 10 so new tests can be inserted. Categories follow `test_<NNNN>_command_<command>_<behavior>.sh`, `test_<NNNN>_command_option_<command>_<option>_<behavior>.sh`, `test_<NNNN>_symmetry_<command_a>_<command_b>.sh`, `test_<NNNN>_workflow_<scenario>.sh`, `test_<NNNN>_contract_<area>.sh`, or `test_<NNNN>_platform_<area>.sh`. Each test file's second line is a `# Test: <one-line description>` header used by `run-all-tests.sh list`. Do not use `wave`, `vawe`, milestone, or implementation-phase names. Tests should print steps with what/why context, show important commands being exercised, state expected results in plain English, and describe concise results. Unexpected assertion results should include `UNEXPECTED RESULT:`. The full suite is long-running and may exceed 10 minutes; that is acceptable while stdio output continues. A test with no output for more than `TEST_WATCHDOG_SECONDS` seconds, default 180, is treated as hung and stops the suite.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects. When work is tied to a ticket, start with the ticket key. Pull requests should describe behavior changes, list tests run, and call out manifest or workflow compatibility risks. Include screenshots only for documentation or terminal-output changes where formatting matters.

## Security & Configuration Tips

Do not store provider tokens or credentials in `.gitnest`. Keep provider integration optional, and prefer `.gitnest-rc` or environment variables for local configuration. Subproject entries must pin `revision=<sha>` and must not depend only on moving branch names.
