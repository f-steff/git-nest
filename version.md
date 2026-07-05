# Version History

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

- Changed name from `git-stack` to `git-lego` to avoid conflicts with a similarly named tool.
- Renamed manifest and terminology from stack/module to project/subproject.
- Renamed `refresh` to `snapshot`, `available` to `outdated`, `check` to `no-pending`, and `foreach-modified` to `foreach-pending`.
- Switched the license from AGPL-3.0-or-later to MIT.
- Added the `.gitlego text eol=lf` `.gitattributes` guard.

## 0.4.2 - 2026-06-29

- Added stale subproject path reconciliation during `git-lego sync`.
- Automatically moves clean, pushed subprojects when manifest paths change.
- Automatically removes clean, pushed subprojects that are no longer in the manifest.
- Added `git-lego sync --prune` for explicit stale local-state cleanup after warnings.
- Documented stale cleanup notices, warnings, and ambiguity handling.

## 0.4.1 - 2026-06-26

- Added porcelain output for `git-lego status` and `git-lego outdated`.
- Expanded `git-lego --help` with brief command and option descriptions.
- Made `.gitlego-rc` optional by default and added `git-lego init --rc`.
- Renamed the local manifest update command from `record` to `snapshot`.
- Propagated managed hooks to subprojects added or cloned after hooks are installed.
- Moved the default integration test root outside the repository.
- Documented script-friendly dirty and outdated checks.

## 0.4.0 - 2026-06-26

- Added `git-lego outdated` for read-only remote outdated checks.
- Added `git-lego upload --finalize` for direct push-and-pin workflows.
- Simplified README positioning, comparison, requirements, and skill guidance.

## 0.3.0 - 2026-06-24

- Added combined project history output with `git-lego log`.
- Documented nested project discovery behavior.

## 0.2.0 - 2026-06-22

- Added recursive handling for status, verify, sync, and log.
- Improved notices when nested projects are present but not included.

## 0.1.0 - 2026-06-20

- Added subproject update modes for target heads, explicit revisions, tags, and branch retargeting.
- Added protections for dirty and pending subprojects during updates.

## 0.0.9 - 2026-06-19

- Added branch cleanup hints and local cleanup support after finalization.
- Preserved remote branches during cleanup.

## 0.0.8 - 2026-06-18

- Added managed Git hook installation and removal.
- Kept hook behavior local and non-pushing.

## 0.0.7 - 2026-06-17

- Added foreach and foreach-pending commands for subproject automation.
- Exported project context variables for subproject commands.

## 0.0.6 - 2026-06-16

- Added upload, pending subproject tracking, no-pending, and finalize workflows.
- Improved manifest state validation before writes.

## 0.0.5 - 2026-06-14

- Added coordinated branch start and local record behavior.
- Added dirty-work preflight handling for branch changes.

## 0.0.4 - 2026-06-12

- Added init, add, sync, status, verify, and version commands.
- Established the `.gitlego` manifest format and subproject layout.
