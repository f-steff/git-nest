# Maintainer Guide

This guide is for changing `git-stack` itself. For user-facing behavior, treat `docs/implementation-summary.md` as the behavior contract and `README.md` as the manual.

## Maintenance Rules

- Keep `GIT_STACK_VERSION=0.4.1` until the version is explicitly changed.
- Keep business logic in `bin/git_stack.sh`; keep `bin/git-stack` and `bin/git-stack.bat` thin.
- Preserve the polyglot behavior of `bin/git-stack.bat` so one IDE build-hook command can work across Windows, Linux, and macOS.
- Write portable `sh` where practical. Prefer `case`, `while`, `sed`, `awk`, `grep`, and `git`.
- Avoid arrays, `mapfile`, process substitution, associative arrays, and Bash-only conveniences unless clearly justified.
- Quote variables and validate required values before Git operations or manifest writes.
- Use `Error:`, `Warning:`, and `Notice:` for user-facing diagnostics.
- Keep manifest rewrites deterministic and readable.
- Do not add mandatory provider integration or automatic PR creation.
- Keep hooks opt-in; hooks may run `git-stack refresh --quiet` but must not push or upload automatically.

## Change Workflow

For behavior changes:

1. Read `docs/implementation-summary.md`.
2. Inspect the relevant command implementation in `bin/git_stack.sh`.
3. Add or update focused integration tests under `tests/`.
4. Update `README.md`, `docs/implementation-summary.md`, `docs/technical_docs.md`, and `skills/git-stack/SKILL.md` when user-facing behavior changes.
5. Run the full suite:

```bat
tests\run-all.bat
```

On POSIX-like systems:

```sh
sh tests/run-all.sh
```

## Testing Expectations

Tests should create local bare Git repositories as remotes under `TEST_ROOT`, identify themselves through `test_begin` for standalone runs, and leave numbered workspaces for inspection. The default `TEST_ROOT` is outside the repository so startup tests are not affected by the tool repository's own Git root. The suite owns formatted headings and the final status/time summary table.

Cover both successful behavior and negative paths. New parser branches, missing refs, dirty/pending protections, manifest state transitions, Git-style invocation, portability paths, and recursive nested-stack behavior should have tests when touched.

## Scope Guardrails

`git-stack` should stay a small, predictable Git orchestration tool. Do not chase full Android `repo` parity. Prefer explicit behavior, clear failure messages, and testable shell code.
