# Repository Guidelines

## Project Structure & Subproject Organization

This repository contains the behavior contract in `docs/command-behavior-contract.md`, the user manual in `README.md`, maintainer guidance in `development/README.md`, and a user-facing AI skill in `skills/git-nest/SKILL.md`.

Keep implementation files organized by responsibility:

```
bin/
  git-nest                  main executable shell entrypoint
  git-nest.bat              polyglot launcher (cmd.exe and sh/bash)
  git-nest.ps1              PowerShell 7+ launcher
  git_nest.sh               thin shared entrypoint: sources bin/lib/;
                            the command dispatch table (git_nest_main) lives
                            in lib/git-nest-commands.sh
  lib/                      library modules (git-nest-manifest.sh,
                            git-nest-commands.sh, git-nest-hooks.sh,
                            git-nest-conversion.sh, git-nest-doctor.sh,
                            parse-gitnest.awk, tree-render.awk)
tests/
  run-all-tests.sh/.bat     main runner (IDs 0000-5050) and cmd.exe launcher
  tests.md                  overall test strategy guide
  docker/                   cross-shell checks in Alpine + Debian
  unit-tests/               function-level suite (mock Git shim),
                            standalone runner, unit-tests.ini coverage map
  integration-tests/        end-to-end suite (real Git repositories),
                            helper.sh, check.sh
docs/                       user-facing documentation (shipped in packages)
development/                repository development/maintenance docs (CI,
                            dockerized testing, POSIX notes, technical
                            implementation) -- not shipped
index.md, _config.yml,      GitHub Pages site (Jekyll, just-the-docs theme):
assets/logo.svg,            rendered from README.md + docs/; see
_includes/head_custom.html  development/github-pages.md
skills/git-nest/SKILL.md    portable AI usage skill shipped to consumers;
                            single source of truth for that skill
.agents/skills/<name>/SKILL.md  skill tree for development agents
schemas/                    JSON output schema
```

## AI Skills And Agent Bootstrap

Development agents bootstrap from this `AGENTS.md` at the repository root. Both Codex and opencode read it, and opencode also loads global rules from `~/.config/opencode/AGENTS.md`.

There are two distinct skill trees. Do not conflate them:

- `skills/` holds product skills shipped to consumers of git-nest. `skills/git-nest/SKILL.md` is the single source of truth for the git-nest usage skill.
- `.agents/skills/` holds the skill tree that development agents discover while working on git-nest. opencode only discovers skills at `.agents/skills/<name>/SKILL.md` (and `.opencode/skills/`, `.claude/skills/`), never at `.agents/<name>/SKILL.md`.

To keep one source of truth without duplicating skill bodies, `.agents/skills/git-nest/SKILL.md` is a thin pointer that redirects agents to `skills/git-nest/SKILL.md`. Development-only skills that never ship, such as `windows-powershell-shell`, live only under `.agents/skills/` and are authoritative there.

When you change the usage skill, edit `skills/git-nest/SKILL.md`. If you change its purpose, keep the pointer's `description` frontmatter matching the source. `tests/integration-tests/test_2070_contract_skills_pointer.sh` enforces this layout.

## Build, Test, and Development Commands

- `sh bin/git-nest --help`: verify command discovery and help output.
- `sh bin/git-nest init`: exercise initialization in a scratch workspace.
- `sh bin/git-nest doctor --offline`: inspect local workspace health without contacting remotes.
- `sh tests/integration-tests/<test-name>.sh`: run an individual integration test.
- `sh tests/run-all-tests.sh`: run the full shell test suite from Git Bash or another POSIX-like shell. The runner resets `${TMPDIR:-/tmp}/git-nest-test-workspaces` (plus stale temp artifacts) at startup and leaves generated repositories in numbered folders. It writes the Markdown summary `run-all-tests-results.md` and captures the full run to `run-all-tests.log` by default; pass `--no-log` to skip the log or `--log FILE` to redirect it. The console shows a curated per-test narrative (step descriptions and each git-nest command with its output); the full raw output is saved per test and printed when a test fails. Pass `--verbose` (`-v`) to stream everything with a shell trace instead, or `--stop-on-fail` to stop at the first failure. The summary table sizes its columns to the longest test name.
- `sh tests/run-all-tests.sh list`: list every test as `ID  description`. `sh tests/run-all-tests.sh only 0130,5010` runs only those test IDs; `except 5000,5010` runs all but those; `cleanup` removes artifacts from previous runs without running tests; `help` prints the commands. An unknown command, option, or test ID prints help and stops.
- `sh tests/unit-tests/run-all-tests.sh`: run the standalone unit suite (also run inside the full suite via `test_0000_unit_tests.sh`).
- `tests\run-all-tests.bat`: run the same suite from `cmd.exe` through Git Bash. It forwards all commands and options (`list`, `only`, `except`, `cleanup`, `help`, `--verbose`, `--stop-on-fail`, `--no-log`, `--log FILE`) to the shell runner.
- `--dry-run` is expected on `restore`, `snapshot`, `freeze`, `gc`, `pull`, `absorb`, `absorb-all`, `inline`, `detach`, and `remove` where supported by the command.

No package manager build is expected for the current release. The tool should remain script-friendly and runnable directly from the checkout.

## Coding Style & Naming Conventions

Write portable shell where practical. Prefer POSIX-style `case`, `while`, `sed`, `awk`, `grep`, and `git` flows over Bash-only features. Avoid arrays, `mapfile`, process substitution, and associative arrays unless the need is clear and documented.

Use lowercase function names with underscores, quote variables, fail with clear error messages, and keep manifest rewrites deterministic. Keep shell implementation files in `bin/` unless the project grows enough to justify a separate library tree.

## Testing Guidelines

git-nest uses a two-tier test strategy: **unit tests are the primary tier**,
integration tests the secondary tier. Prefer writing a unit test first; reach
for an integration test only when the behavior genuinely depends on real Git
repositories or command end-to-end flow.

- **Primary tier -- unit tests** (`tests/unit-tests/`, IDs 1000-1999): test
  individual functions in isolation using the mock Git shim, so they run fast
  and catch edge cases without creating real repositories. Add a
  `# Coverage: <function>` header per covered function; the coverage report
  and test 1990 enforce that every function is either covered or deliberately
  catalogued in `unit-tests.ini [untested]`. Start here for any new or changed
  function.
- **Secondary tier -- integration tests** (`tests/integration-tests/`, IDs
  0010-5050): create local bare Git repositories as remotes under the
  configured `TEST_ROOT` (which defaults outside the repository) and run
  `git-nest` commands end-to-end. Use these for command behavior, workflows,
  hooks, and cases that need a real checkout. Cover both clean paths and
  failure paths for `init`, `tidy`, `add`, `snapshot`, `restore`, hooks,
  branch marks, and update/restore safety behavior, including startup from
  empty folders and restore with partial subproject failures. The unit suite
  runs inside the full suite via `test_0000_unit_tests.sh`; the Docker
  cross-shell runner covers syntax, unit, and `__complete` checks.
  `git-nest doctor --offline` is a useful preflight before running the suite.

Name tests by feature, never by development phase, and give each a globally unique four-digit ID prefix so the runner can list and select them. Files are named `test_<NNNN>_<category>_<behavior>.sh` under `tests/integration-tests/`, where the ID blocks are: `command_*` from 0010, `contract_*` from 2000, `platform_*` from 3000, `symmetry_*` from 4000, and `workflow_*` from 5000, each stepping by 10 so new tests can be inserted (IDs `0000` for the unit-suite bridge and `0004` for static code analysis are reserved exceptions; a `0205`-style insertion is allowed between blocks). Unit tests use `unit-test_<NNNN>_<name>.sh` under `tests/unit-tests/`. Categories follow `test_<NNNN>_command_<command>_<behavior>.sh`, `test_<NNNN>_command_option_<command>_<option>_<behavior>.sh`, `test_<NNNN>_symmetry_<command_a>_<command_b>.sh`, `test_<NNNN>_workflow_<scenario>.sh`, `test_<NNNN>_contract_<area>.sh`, or `test_<NNNN>_platform_<area>.sh`. Each test file's second line is a `# Test: <one-line description>` header used by `run-all-tests.sh list`. Do not use `wave`, `vawe`, milestone, or implementation-phase names. Tests should print steps with what/why context, show important commands being exercised, state expected results in plain English, and describe concise results. Unexpected assertion results should include `UNEXPECTED RESULT:`. The full suite is long-running and may exceed 30 minutes; that is acceptable while stdio output continues. A test with no output for more than `TEST_WATCHDOG_SECONDS` seconds, default 180, is treated as hung and stops the suite.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects. When work is tied to a ticket, start with the ticket key. Pull requests should describe behavior changes, list tests run, and call out manifest or workflow compatibility risks. Include screenshots only for documentation or terminal-output changes where formatting matters.

## Security & Configuration Tips

Do not store provider tokens or credentials in `.gitnest`. Keep provider integration optional, and prefer `.gitnest-rc` or environment variables for local configuration. Subproject entries must pin `revision=<sha>` and must not depend only on moving branch names.
