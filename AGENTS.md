# Repository Guidelines

## Project Structure & Module Organization

This repository contains the behavior contract in `docs/implementation-summary.md`, the user manual in `README.md`, maintainer guidance in `docs/maintainer.md`, and a user-facing AI skill in `skills/git-stack/`.

Keep implementation files organized by responsibility:

- `bin/git-stack`: main executable shell entrypoint.
- `bin/git-stack.bat`: thin polyglot launcher that works from `cmd.exe` and sh/bash contexts, then forwards to the shell script.
- `bin/git_stack.sh`: command, manifest, Git, branching, and finalize helpers sourced by the entrypoint.
- `tests/*.sh`: shell-based integration tests using temporary repositories.
- `docs/`: user-facing and technical documentation.
- `skills/git-stack/`: portable AI skill for agents working in projects that consume git-stack.

The source of truth for behavior is `docs/implementation-summary.md`; the earlier submodule script was only a style and portability reference.

## Build, Test, and Development Commands

- `sh bin/git-stack --help`: verify command discovery and help output.
- `sh bin/git-stack init`: exercise initialization in a scratch workspace.
- `sh tests/<test-name>.sh`: run an individual integration test.
- `sh tests/run-all.sh`: run the full shell test suite from Git Bash or another POSIX-like shell. The runner resets `${TMPDIR:-/tmp}/git-stack-test-workspaces` at startup and leaves generated repositories in numbered folders such as `test_01_auto_finalize/`.
- `tests\run-all.bat`: run the same suite from `cmd.exe` through Git Bash.

No package manager build is expected for v0.4. The tool should remain script-friendly and runnable directly from the checkout.

## Coding Style & Naming Conventions

Write portable shell where practical. Prefer POSIX-style `case`, `while`, `sed`, `awk`, `grep`, and `git` flows over Bash-only features. Avoid arrays, `mapfile`, process substitution, and associative arrays unless the need is clear and documented.

Use lowercase function names with underscores, quote variables, fail with clear error messages, and keep manifest rewrites deterministic. Keep shell implementation files in `bin/` unless the project grows enough to justify a separate library tree.

## Testing Guidelines

Tests should be integration-oriented and create local bare Git repositories as remotes under the configured `TEST_ROOT`, which defaults outside the repository. Cover both clean paths and failure paths for `init`, `add`, `start`, `upload`, `finalize`, and `sync`, including startup from empty folders and sync with partial module failures. Name tests by behavior, such as `test_finalize_revision.sh` or `test_upload_records_pending.sh`.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects. When work is tied to a ticket, start with the ticket key, for example `XX-123: Add finalize revision mode`. Pull requests should describe behavior changes, list tests run, and call out manifest or workflow compatibility risks. Include screenshots only for documentation or terminal-output changes where formatting matters.

## Security & Configuration Tips

Do not store provider tokens or credentials in `.stack`. Keep provider integration optional, and prefer `.stack-rc` or environment variables for local configuration. Finalized module entries must pin `revision=<sha>` and must not depend only on moving branch names.
