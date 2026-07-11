# Version History

## 0.8.1 - 2026-07-08

- Changed name from `git-lego` to `git-nest` to better reflect the tool's role as a shared home for independent Git repositories and to avoid using the name of a commercial product.
- Renamed the command surface from `git-lego` / `git lego` to `git-nest` / `git nest`.
- Renamed project-owned state from `.gitlego` and `.gitlego-rc` to `.gitnest` and `.gitnest-rc`.
- Renamed implementation, schema, documentation, tests, and the portable AI skill to use the `git-nest` name.
- Preserved the historical `git-stack` name and stack/module terminology in pre-0.5.0 version history entries.
- Added the `\\_oOO_//` nest-and-eggs logo after the name and version in version command output, keeping the first two fields script-friendly.
- Added platform-specific installation and invocation guidance for Windows, Linux, and macOS.
- Added a README command quick reference with a brief purpose statement for each command.
- Added grouped help output and `git-nest help <command>` pages with command-specific explanations, examples, and symmetric command guidance.
- Clarified `git-nest clone <nest-repo-url>` as a `git clone` plus `git-nest restore` convenience, distinct from subproject `clone-mode`.
- Clarified `config` as an allowlisted manifest setting command; currently only `clone-mode=full|partial` is public, and unknown keys are rejected.
- Added `doctor` informational checks for optional export helpers: system `tar` for `tar.gz` output and `python` / `python3` for `zip` output.
- Updated generated test result tables so test names render as inline code.
- Added `todo.md` to track pending design work, documentation suggestions, and completed release tasks.
- Cleaned up `todo.md` into active todo, suggestions, and done sections, including future submodule/subtree/git-subrepo conversion design notes.
- Reworked the workflow around normal Git branch, commit, and push operations plus `git-nest snapshot` for recording reproducible subproject revisions.
- Replaced the public `sync` command with `restore`, so restoring files from the manifest is named separately from recording manifest state.
- Removed the public branch/upload/finalize/pending workflow commands; old names now fail with guidance toward the new workflow.
- Added `repair` so `init` creates only, while managed support files are refreshed explicitly.
- Added local branch-memory commands: `branch-mark`, `branch-unmark`, `branch-list`, and `branch-cleanup`.
- Added `move` as the long-form alias for `mv`, matching `remove` / `rm` symmetry.
- Renamed hook management to `hooks-install` and `hooks-uninstall`, and split root and subproject hook behavior around restore/snapshot reproducibility.
- Added nested `init --sure` protection so accidental nests inside managed subprojects are rejected by default.
- Updated README, implementation summary, maintainer guidance, AGENTS.md, and the portable AI skill for the restore/snapshot model.

## 0.7.1 - 2026-07-04

Polish and hardening release. No breaking changes.

- Added: `git-lego doctor` command for environmental preflight checks.
- Added: `--dry-run` support on `sync`, `snapshot`, `upload`, and `finalize`.
- Added: README "Limitations And Non-Goals" section.
- Added: README "Recovery Cookbook" section.
- Added: README per-command side-effect matrix.
- Hardened: backslash path refusal across write-side commands that accept subproject paths.
- Hardened: reserved-name and `.git` segment refusal for subproject paths.
- Hardened: `git-lego init` now repairs the managed `.gitattributes` block for git-lego line endings.
- Documentation: README, skill guidance, technical notes, implementation summary, AGENTS.md, and maintainer guide updated for 0.7.1.
- Schema: `git-lego-output-v1.schema.json` extended to cover `doctor` output and dry-run markers, backward-compatible.

## 0.7.0 - 2026-07-03

- Added project-boundary checks so write-side commands refuse parent-to-nested-project path crossings:
  - `add`, `remove`, `mv`, `config`, `freeze`, and `snapshot` now operate inside the current project boundary.
- Added `snapshot --recursive` as the migration path for checked-out nested projects that previously relied on root-level automatic recursion.
- Added `extract` to convert tracked outer directories into managed subprojects.
- Added `absorb` to convert managed subprojects back into outer-repository files.
- Internal: Centralized manifest lookup in `find_owning_manifest` helper; no user-visible change.

## 0.6.3 - 2026-07-03

- Added `export` for directory, tar.gz, and zip source snapshots with generated `MANIFEST.lock`.
- Added deterministic archive output, dirty subproject protection, and `--allow-dirty`.
- Added explicit dirty-and-pending status porcelain rows.

## 0.6.2 - 2026-07-03

- Added `completion <bash|zsh|fish>` for command, option, and subproject path completion.
- Documented shell completion installation examples.

## 0.6.1 - 2026-07-03

- Added `diff` for reviewing subproject commits relative to manifest-recorded revisions, including `--since`, `--stat`, and JSON output.
- Added manifest-backed `config` management for subproject `clone-mode`.
- Added `foreach-modified` and `foreach-clean` filters with porcelain and JSON listing modes.

## 0.6.0 - 2026-07-03

- Added core workspace maintenance commands: `remove`, `rm`, `mv`, `clone`, and `freeze`.
- Added unmanaged nested repository detection in `status` and `verify`.
- Relaxed manifest extension handling so unknown sections and keys are preserved.
- Added `.gitignore` hygiene guards for nested `.git` directories.

## 0.5.2 - 2026-07-03

- Added fixed-column porcelain output and JSON output for script-facing commands.
- Added the command output JSON Schema at `schemas/git-lego-output-v1.schema.json`.
- Documented and exercised exit-code conventions, including `status --exit-code`.

## 0.5.1 - 2026-07-03

- Added mandatory `.gitlego` manifest schema `version=1` and `MANIFEST.md`.
- Added command-scoped `.gitlego.lock` protection for manifest writers.
- Hardened auto-finalize ticket matching, base revision resolution, tag drift checks, and `.gitignore` deduplication.
- Added README security considerations.

## 0.5.0 - 2026-07-03

- Changed name from `git-stack` to `git-lego` to avoid confusion with another `git-stack` tool with radically different features.
- Renamed manifest and terminology from stack/module to project/subproject.
- Renamed `refresh` to `snapshot`, `available` to `outdated`, `check` to `no-pending`, and `foreach-modified` to `foreach-pending`.
- Switched the license from AGPL-3.0-or-later to MIT.
- Added the `.gitlego text eol=lf` `.gitattributes` guard.

Historical note: releases before 0.5.0 were published as `git-stack`. Version
0.5.0 is the rename boundary where the tool became `git-lego` to avoid
confusion with another `git-stack` tool with radically different features.
Pre-0.5.0 entries therefore use the old command name, stack/module terminology,
and legacy command names as they existed at the time.

## 0.4.2 - 2026-06-29

- Added stale module path reconciliation during `git-stack sync`.
- Automatically moves clean, pushed modules when manifest paths change.
- Automatically removes clean, pushed modules that are no longer in the manifest.
- Added `git-stack sync --prune` for explicit stale local-state cleanup after warnings.
- Documented stale cleanup notices, warnings, and ambiguity handling.

## 0.4.1 - 2026-06-26

- Added porcelain output for `git-stack status` and `git-stack available`.
- Expanded `git-stack --help` with brief command and option descriptions.
- Made local rc configuration optional by default and added `git-stack init --rc`.
- Renamed the local manifest update command from `record` to `refresh`.
- Propagated managed hooks to modules added or cloned after hooks are installed.
- Moved the default integration test root outside the repository.
- Documented script-friendly dirty and available checks.

## 0.4.0 - 2026-06-26

- Added `git-stack available` for read-only remote availability checks.
- Added `git-stack upload --finalize` for direct push-and-pin workflows.
- Simplified README positioning, comparison, requirements, and skill guidance.

## 0.3.0 - 2026-06-24

- Added combined stack history output with `git-stack log`.
- Documented nested stack discovery behavior.

## 0.2.0 - 2026-06-22

- Added recursive handling for status, verify, sync, and log.
- Improved notices when nested stacks are present but not included.

## 0.1.0 - 2026-06-20

- Added module update modes for target heads, explicit revisions, tags, and branch retargeting.
- Added protections for dirty and pending modules during updates.

## 0.0.9 - 2026-06-19

- Added branch cleanup hints and local cleanup support after finalization.
- Preserved remote branches during cleanup.

## 0.0.8 - 2026-06-18

- Added managed Git hook installation and removal.
- Kept hook behavior local and non-pushing.

## 0.0.7 - 2026-06-17

- Added foreach and foreach-modified commands for module automation.
- Exported stack context variables for module commands.

## 0.0.6 - 2026-06-16

- Added upload, pending module tracking, check, and finalize workflows.
- Improved manifest state validation before writes.

## 0.0.5 - 2026-06-14

- Added coordinated branch start and local record behavior.
- Added dirty-work preflight handling for branch changes.

## 0.0.4 - 2026-06-12

- Added init, add, sync, status, verify, and version commands.
- Established the manifest format and module layout.
