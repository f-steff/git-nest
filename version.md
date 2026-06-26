# Version History

## 0.4.1 - 2026-06-26

- Added porcelain output for `git-stack status` and `git-stack available`.
- Expanded `git-stack --help` with brief command and option descriptions.
- Made `.stack-rc` optional by default and added `git-stack init --rc`.
- Renamed the local manifest update command from `record` to `refresh`.
- Propagated managed hooks to modules added or cloned after hooks are installed.
- Moved the default integration test root outside the repository.
- Documented script-friendly dirty and availability checks.

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
- Established the `.stack` manifest format and stack module layout.
