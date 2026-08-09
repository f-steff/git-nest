---
layout: default
title: Exit Codes
nav_order: 7
---

# Exit Codes

`git-nest` uses the following exit codes for scripting:

| Code | Constant | Meaning |
| --- | --- | --- |
| 0 | -- | Success. |
| 1 | `EXIT_ISSUES` | Command completed but found issues: dirty or missing subprojects, drift, or other problems. For example, `status --exit-code` returns 1 when dirty rows exist. |
| 2 | `EXIT_USAGE` | Invalid command, flag, or argument. The `Error:` message on stderr describes the problem. |
| 3 | `EXIT_PRECONDITION` | The command cannot run because the workspace is not ready: no `.gitnest` file, missing Git, unsafe path, or a required value is missing. |
| 4 | `EXIT_LOCK` | Could not acquire the manifest lock within the configured timeout (`GIT_NEST_LOCK_TIMEOUT_SECONDS`, default 10 seconds). The lock owner PID and creation time are reported so the user can identify and clear a stale lock. |
| 5 | `EXIT_GIT` | A Git command (clone, fetch, push, checkout, etc.) failed. The error output from Git is printed on stderr. |

Nonzero exit codes do not automatically mean a bug. Many commands document specific exit-code behavior:

- `status --exit-code` returns 1 when the workspace has dirty or missing rows.
- `outdated --porcelain` / `outdated --json` return 1 when newer remote commits, missing checkouts, or remote query problems are found.
- `snapshot --check --strict` returns 3 for missing subprojects and 1 for dirty or unreproducible subprojects.
- `doctor --exit-code` returns 1 when warnings or errors are present in the health report.
- `verify` returns 1 when validation errors are found.
