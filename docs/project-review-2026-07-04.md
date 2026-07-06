# Project review: git-lego

Date: 2026-07-04

> Scope note: this review is based on the repository contract and project layout visible in `AGENTS.md` (`README.md`, `docs/implementation-summary.md`, `bin/git-lego`, `bin/git-lego.bat`, `bin/git_lego.sh`, shell integration tests, and `skills/git-lego/`). Local command execution was unavailable in this review session, so items that require runtime confirmation are marked as validation targets.

## Executive summary

`git-lego` is a useful idea: it targets the common gap between monorepos and submodules by offering a manifest-driven stack of independent Git repositories that can be initialized, worked on, uploaded, finalized, and synced together. The project is strongest when it behaves as a small, predictable workflow tool rather than a hidden abstraction over Git.

The main product risk is not the concept; it is workflow ambiguity. Users need to understand which commands mutate local checkouts, which commands mutate remotes, which commands rewrite the manifest, and which commands are safe to retry. The highest-return improvements are therefore in command symmetry, dry-run/status output, clearer failure recovery, and deterministic edge-case handling.

## Product idea and positioning

### What works well

- The tool solves a real problem for teams that need multiple repos to move together without fully committing to Git submodules or a monorepo.
- A plain manifest (`.gitlego`) is approachable, reviewable, and CI-friendly.
- The workflow vocabulary (`init`, `add`, `start`, `upload`, `finalize`, `sync`) maps reasonably well to the lifecycle of a coordinated multi-repo change.
- Pinning finalized entries with `revision=<sha>` is the right safety model for reproducibility.
- Providing an AI skill in `skills/git-lego/` is a differentiator: it helps agents consume the workflow consistently in downstream projects.

### Main concern

The current command set appears lifecycle-oriented, but the names do not fully reveal side effects. For example, a new user may not know whether `sync` changes local branches, whether `upload` pushes all subprojects or only dirty ones, whether `finalize` records local HEADs or remote-tracking revisions, or whether `start` creates missing branches locally, remotely, or both.

### Actionable recommendations

1. Add a one-screen "mental model" section to the README:
   - Workspace repo contains `.gitlego`.
   - Subprojects are normal Git repos.
   - Branch mode tracks coordinated work.
   - Finalized mode pins exact commits.
   - Manifest changes are ordinary Git changes.
2. Add a side-effect matrix for every command:
   - Reads manifest?
   - Writes manifest?
   - Creates directories?
   - Creates/checks out branches?
   - Commits?
   - Pushes?
   - Requires clean working trees?
3. Explicitly state the "escape hatch": users can always `cd` into a subproject and use normal Git, but must run `git-lego sync/status/finalize` to reconcile manifest state.

## Command design and symmetry

### Current command lifecycle

The lifecycle implied by the project is:

1. `init` creates a workspace manifest.
2. `add` registers subprojects.
3. `start` creates or switches coordinated work branches.
4. `upload` pushes work and records pending/finalization metadata.
5. `finalize` pins exact revisions.
6. `sync` reconciles local checkout state with manifest state.

That lifecycle is coherent, but users will look for missing counterpart commands.

### Low-hanging command improvements

#### Add `status`

This is the most important missing usability command. Before users trust mutating commands, they need a read-only command that answers:

- Is the root manifest present and valid?
- Which subprojects are missing locally?
- Which subprojects have dirty working trees?
- Which subprojects are on the expected branch?
- Which subprojects are ahead/behind their upstream?
- Which manifest entries are finalized by revision versus floating by branch?
- Which operations would `sync`, `upload`, or `finalize` perform?

Suggested shape:

```text
git lego status
git lego status --porcelain
git lego status --json
```

#### Add `plan` or `--dry-run` everywhere

Every mutating command should support a dry-run mode, especially:

- `add --dry-run`
- `start --dry-run`
- `sync --dry-run`
- `upload --dry-run`
- `finalize --dry-run`

The output should be deterministic and copy-pasteable into issue reports.

#### Add `remove`

If `add` exists, users will expect `remove`. Without it, they must hand-edit `.gitlego`, which is acceptable for advanced users but unfriendly for early adoption.

Important cases:

- Remove only from manifest.
- Optionally delete local checkout directory.
- Refuse to delete dirty subprojects unless explicitly forced.

Suggested shape:

```text
git lego remove <name>
git lego remove <name> --delete-working-tree
git lego remove <name> --force
```

#### Add `rename` or document manual rename

If manifest entries have stable names/paths, renaming can be error-prone. Either provide `rename` or document the manual procedure.

#### Add `doctor`

This can be an alias or superset of validation:

- Manifest syntax check.
- Duplicate names/paths.
- Paths escaping the workspace.
- Missing `revision` in finalized state.
- Unreachable remotes.
- Branch names that differ from expected naming conventions.
- Local paths that are not Git repositories.

## Usability edge cases to handle explicitly

### Empty directory startup

The tests are expected to cover startup from empty folders. The UX should still be clear:

- If no `.gitlego` exists, commands other than `init` should say exactly that.
- Error messages should suggest `git lego init`.
- Commands should not silently create a manifest unless the command is `init`.

### Re-running commands

All commands should be idempotent where practical:

- `init` on an existing workspace should be a no-op or explicit refusal with a helpful message.
- `add` for an already registered URL/path should refuse with a clear duplicate explanation.
- `start` for an already-started branch should report "already on branch" rather than fail.
- `upload` should be safe to retry after partial push failures.
- `finalize` should be safe to retry and produce the same manifest if HEADs did not change.
- `sync` should be safe to retry after partial clone/checkout failures.

### Dirty working trees

This is likely the most common way users will rub against the tool. Each command should document and consistently enforce whether dirty subprojects are allowed:

- `sync`: should refuse to overwrite or checkout across dirty work unless forced.
- `start`: should refuse branch switches that would overwrite changes.
- `finalize`: should clarify whether dirty but committed HEADs can be finalized, and whether uncommitted changes block finalization.
- `upload`: should clarify whether it pushes only committed work and how it reports uncommitted files.

Low-hanging improvement: add a shared "dirty tree summary" helper that prints the same format for every command.

### Detached HEAD and finalized revisions

Finalized entries pin commits, so sync may put subprojects into detached HEAD. That is correct but surprising. The tool should print a clear message:

- "Checked out pinned revision `<sha>`; this subproject is in detached HEAD."
- "Run `git lego start <branch>` to resume branch-based work."

### Branch names and default branches

Potential edge cases:

- Remote default branch is `main`, `master`, or unset.
- Local default branch differs from remote default branch.
- Requested work branch exists locally but points to a different commit than the remote branch.
- Requested work branch exists remotely but not locally.
- Branch contains slashes or shell-special characters.

Recommendation: centralize branch validation and quote branch names in all messages.

### Manifest path safety

Manifest paths should be treated as untrusted input, even though they are local files. Validate that subproject paths:

- Are relative paths.
- Do not contain `..` path traversal.
- Do not resolve outside the workspace.
- Do not point to the workspace root.
- Do not collide with `.git`, `.gitlego`, or another subproject path.

This matters for both user safety and CI/devops usage.

### Duplicate and overlapping entries

The manifest should reject:

- Duplicate subproject names.
- Duplicate checkout paths.
- Nested paths unless explicitly supported.
- Same remote URL under two names unless explicitly allowed.

Nested subprojects are especially risky because recursive status, sync, or delete operations can affect the wrong checkout.

### Partial failures

The docs mention sync with partial subproject failures. The implementation should make partial failure behavior a first-class contract:

- Continue or stop policy must be explicit.
- Exit code should be non-zero if any subproject failed.
- Summary should list successes, skips, and failures.
- Retry instructions should be printed.
- No manifest rewrite should occur after an unrecoverable partial failure unless the command clearly documents partial updates.

### Authentication and remote failures

Devops users will hit non-interactive authentication failures in CI. Commands should distinguish:

- Remote URL invalid.
- Network unavailable.
- Authentication required.
- Push rejected.
- No upstream configured.
- Branch protection rejected push.

Recommendation: preserve Git's stderr but prefix each operation with the subproject name, so logs are searchable.

### Shallow clones and missing revisions

If CI or users clone subprojects shallowly, `sync` to a pinned revision may fail because the object is missing. The tool should either fetch the specific revision or print a precise error:

- "Revision `<sha>` for `<name>` is not present locally and could not be fetched from `<remote>`."

### Windows and path portability

The project includes `bin/git-lego.bat`, which is good. Watch these cases:

- Paths with spaces.
- Drive-letter paths.
- Git Bash versus `cmd.exe` invocation.
- CRLF in `.gitlego`.
- Shell scripts sourced from Windows paths.
- Executable bit absent after checkout on Windows.

Low-hanging fruit: add tests with a workspace path containing spaces.

## Implementation review themes

### Keep shell helpers small and shared

The split between `bin/git-lego` and `bin/git_lego.sh` is appropriate. To keep behavior consistent, the implementation should avoid each command reimplementing its own parsing, Git checks, dirty-tree checks, and manifest rewrites.

High-value shared helpers:

- `die`
- `info` / `warn`
- `require_manifest`
- `load_manifest`
- `validate_manifest`
- `for_each_project`
- `project_git`
- `is_dirty`
- `current_branch`
- `has_remote_branch`
- `safe_checkout`
- `rewrite_manifest_atomic`

### Atomic manifest rewrites

Manifest rewrites should be atomic:

1. Write to a temporary file in the same directory.
2. Validate the temporary file.
3. Move it over `.gitlego`.

If a command is interrupted, the original manifest should remain valid.

### Deterministic ordering

The repository guidelines already call for deterministic rewrites. This should apply to:

- Manifest entry order.
- Output summaries.
- Test assertions.
- JSON/porcelain output, if added.

### Exit code contract

Document exit codes, even if simple:

- `0`: all requested work succeeded.
- `1`: user/actionable failure.
- `2`: invalid usage.
- Optional higher codes for partial failures.

This is particularly useful for CI and scripted adoption.

### Avoid hidden commits

Unless the contract explicitly says otherwise, the tool should not create Git commits in the root or subprojects automatically. Users and CI systems should be able to inspect manifest changes before committing.

If a command does commit, its commit message format and failure modes should be documented.

## User perspective

### What users need most

- "What will this command do?"
- "What changed?"
- "How do I recover?"
- "Can I use normal Git inside subprojects?"

### Low-hanging UX improvements

1. Add `git lego status`.
2. Add `--dry-run` to all mutating commands.
3. Add `--verbose` and `--quiet`.
4. Add command examples for the happy path and recovery path.
5. Add a "common errors" section:
   - Missing manifest.
   - Dirty subproject.
   - Push rejected.
   - Missing remote branch.
   - Finalized revision not found.
6. Print next-step hints after successful commands:
   - After `init`: "Next: `git lego add ...`"
   - After `add`: "Next: `git lego sync` or `git lego start <branch>`"
   - After `start`: "Next: commit in subprojects, then `git lego upload`"
   - After `upload`: "Next: open PRs or `git lego finalize`"
   - After `finalize`: "Review and commit `.gitlego`"

## Developer perspective

### Strengths

- Shell-based implementation keeps dependencies low.
- Integration tests using temporary Git repositories are the right testing strategy.
- A documented behavior contract in `docs/implementation-summary.md` reduces ambiguity.

### Improvements

1. Add a contributor "test matrix" covering:
   - Git Bash on Windows.
   - Linux/macOS POSIX shell.
   - `cmd.exe` launcher.
   - Path with spaces.
   - CRLF checkout.
2. Add fixture helpers for test remotes and subprojects so new tests are cheap.
3. Add focused tests for negative cases:
   - Duplicate manifest entries.
   - Dirty tree blocking.
   - Missing remote.
   - Push rejected.
   - Interrupted/failed manifest rewrite.
   - Partial sync failure.
4. Add a shell lint target if possible (`shellcheck` optional, not mandatory for runtime).
5. Make the implementation summary the acceptance-test checklist.

## Devops perspective

### CI/CD requirements

Devops users need non-interactive, reproducible behavior. Prioritize:

- `--no-interactive` or guaranteed non-interactive defaults.
- Machine-readable status output.
- Stable exit codes.
- Pinned revisions for deploy/release states.
- Clear logs with subproject prefixes.
- No credential persistence.
- No implicit writes outside the workspace.

### Suggested CI commands

Document examples such as:

```sh
git lego doctor
git lego sync --frozen
git lego status --porcelain
```

`--frozen` would mean: fail if the manifest is invalid, a pinned revision cannot be checked out, or any command would rewrite `.gitlego`.

### Release/reproducibility risks

- Floating branch entries are not reproducible.
- Finalized entries must always include `revision=<sha>`.
- CI should be able to reject manifests that contain branch-only entries in release contexts.

Low-hanging fruit: add `git lego doctor --release` or `git lego validate --finalized`.

## Documentation recommendations

### README

Add these sections near the top:

1. "When to use git-lego instead of submodules or a monorepo"
2. "Mental model"
3. "Command side effects"
4. "Recovery cookbook"
5. "CI usage"

### Implementation summary

Make this document stricter by defining:

- Manifest grammar.
- Allowed path format.
- Command preconditions.
- Command postconditions.
- Exit code meanings.
- Partial failure behavior.

### Maintainer guide

Add a release checklist:

- Run full test suite from Git Bash.
- Run batch launcher tests from `cmd.exe`.
- Run path-with-spaces tests.
- Verify docs examples still work.
- Verify finalized entries always pin revisions.

## Suggested priority list

### P0 / correctness and safety

- Validate manifest paths cannot escape the workspace.
- Ensure finalized entries always pin `revision=<sha>`.
- Refuse destructive checkout/sync operations on dirty subprojects.
- Make partial failure exit codes non-zero and summarize failures.

### P1 / adoption and trust

- Add `status`.
- Add `--dry-run` for mutating commands.
- Add consistent command summaries and next-step hints.
- Add path-with-spaces and dirty-tree integration tests.

### P2 / workflow completeness

- Add `remove`.
- Add `doctor` / `validate`.
- Add machine-readable output for CI.
- Document exit codes.

### P3 / polish

- Add shell completion.
- Add shorter aliases if desired.
- Improve examples and screenshots/terminal captures.
- Add troubleshooting examples for common Git errors.

## Edge-case checklist

Use this as an implementation and test checklist:

- [ ] Running outside a workspace.
- [ ] Running in an empty folder.
- [ ] Running inside a subproject instead of the root.
- [ ] Existing `.gitlego` with CRLF line endings.
- [ ] Manifest with blank lines and comments.
- [ ] Duplicate project name.
- [ ] Duplicate path.
- [ ] Nested project paths.
- [ ] Path containing spaces.
- [ ] Path containing `..`.
- [ ] Path resolving outside workspace.
- [ ] Remote URL unreachable.
- [ ] Remote requires authentication in non-interactive CI.
- [ ] Remote default branch missing or renamed.
- [ ] Local branch exists with no upstream.
- [ ] Remote branch exists but local branch does not.
- [ ] Local branch diverged from upstream.
- [ ] Detached HEAD before `start`.
- [ ] Dirty working tree before `sync`.
- [ ] Untracked files that would be overwritten by checkout.
- [ ] Subproject has unpushed commits.
- [ ] Push rejected by branch protection.
- [ ] Finalized revision missing from shallow clone.
- [ ] Interrupted manifest rewrite.
- [ ] Partial clone/sync failure.
- [ ] Re-running every command after partial failure.

## Bottom line

The project idea is sound and useful. The implementation direction is appropriately lightweight, but the tool will earn user trust only if it is extremely explicit about side effects and failure recovery. The best low-hanging fruit is a read-only `status` command, universal dry-run support, stricter manifest validation, and more tests around dirty trees, path safety, Windows paths, and partial failures.
