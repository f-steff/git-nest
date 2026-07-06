# Prioritized Gaps

These are larger reliability or workflow gaps found during the July 2026 recovery-path audit. They are intentionally separated from the immediate patch because each item needs design or profiling rather than a rushed fix.

## P2: Full Suite Runtime And Progress On Windows

The Windows batch suite can exceed 10 minutes in this environment. That runtime is acceptable, but the suite must keep producing regular stdio output and must fail clearly when a test stops producing output for several minutes. The runner now streams test output while capturing logs, records total suite time in `test-result.md`, and uses `TEST_WATCHDOG_SECONDS` to fail silent tests and stop the suite after the first hung test.

Next steps:

- Profile per-test runtime from `test-result.md` and `.run-all-results`.
- Split slow end-to-end tests from fast pre-merge tests, or parallelize independent integration tests.
- Keep long tests chatty enough that healthy work emits output before the watchdog threshold.

## P1: Transactional Recovery For Shape-Changing Commands

`extract` and `absorb` preflight many unsafe states and keep backups where needed, but they are not fully transactional across every possible filesystem or Git failure after mutation begins.

Next steps:

- Add a small recovery journal for `extract` and `absorb`.
- Provide an explicit `git-lego recover` or documented manual recovery flow generated from that journal.
- Extend tests with injected filesystem/Git failures after backup creation.

## P2: Runtime Push Failure After Upload Starts

`upload` now preflights every changed subproject before pushing, which prevents predictable failures such as a missing `origin` from partially pushing earlier subprojects. A server-side or network push rejection can still happen after earlier subproject pushes have succeeded.

Next steps:

- Record a short upload attempt journal before the first push.
- Include pushed branch names and manifest state in failure output.
- Consider an optional cleanup helper for local manifest state and remote branches, while keeping remote branch deletion explicit.

## P2: Sync Partial Materialization Cleanup

`sync` attempts every subproject and now prints aggregate recovery guidance. A failed checkout/tag/ref validation can still leave a newly cloned checkout on disk for the user to inspect or retry.

Next steps:

- Decide whether newly cloned-but-unsynced checkouts should be automatically removed on failure.
- If not removed, add a clearer marker in local materialization state or doctor output.
- Add tests for clone succeeds but checkout/tag validation fails.
