# Local vs CI Testing Differences

GitHub Actions CI is the expensive confirmation, not the first-line
debugger. Every CI-only failure costs a full round-trip (full Linux
~2.5 min, macOS ~6 min, Windows ~40 min on GitHub-hosted runners), so
the goal is to catch as much as possible locally first.

## The push rule

**The complete local suite must pass before anything is pushed.**
`sh tests/run-all-tests.sh` green -> push -> manually dispatch the
three full workflows -> CI green. Pushing earlier turns CI into a
remote debugger and wastes the most expensive resource in the loop.

## When a CI run fails: analysis checklist

1. CI runs `sh tests/run-all-tests.sh --stop-on-fail` -- the log shows
   **only the tests up to the first failure**. Fix the FIRST failure,
   never the last line of the log.
2. Check which workflow actually ran the failing test. The *fast*
   workflows run a fixed set (`0000,0004,0100,2090,3000,3010,3020,3030`);
   everything else (e.g. `test_0117` interactive, `test_2095` links)
   runs only in the full workflows. A test can pass locally yet never
   have run on the workflow you are looking at.
3. Ask: is the failure environmental rather than logical? See the
   catalog below. Reproduce with the runner's environment in mind
   (git defaults, TMPDIR layout, physical-vs-logical paths, tool
   availability, Windows link semantics).
4. Locally-skipped tests are NOT skipped on CI. A test that skips on
   your machine (e.g. busybox) still runs -- and gates -- CI.

## Catalog of known local-vs-CI differences

| # | Difference | Symptom seen | Root cause | Prevention |
|---|------------|--------------|------------|------------|
| 1 | Git defaults differ | `test_0117` asserted `outer branch: main`; CI Linux `git init` created `master` | CI runners have no `init.defaultBranch`; dev machines often do | Never assert branch names from a bare `git init`; use `make_repo`/`init -b` or branch-agnostic assertions |
| 2 | macOS `TMPDIR` ends in `/` | Path assertions failed with a doubled slash (`/var/folders/.../T//git-nest-test-workspaces`) | `TEST_ROOT=${TMPDIR:-/tmp}/...` inherits the trailing slash; shell `pwd` normalizes `//`, shell variables do not | Compare paths via suffixes or normalized `pwd` output, never raw variable concatenation |
| 3 | Logical vs physical paths | Browser anchors duplicated for one folder on macOS + Windows | `find_project_root` returns physical paths (readlink/`cd -P`); shell `pwd` reports the logical path (`/var` -> `/private/var` on macOS, junctions on Windows) | Normalize all session path state with `pwd -P` before comparing (see the anchor dedup test in `test_2095`) |
| 4 | Tool availability differs | `test_3000` skipped locally but ran (and gated) CI | busybox installed on CI runners; this dev machine keeps it at `C:\bin\busybox` via `BUSYBOX_EXE` | Know your local skips; they still run on CI. `BUSYBOX_EXE` or `C:\busybox\bin\busybox.exe` is what `test_3000` checks. Trap: MobaXterm's bundled busybox (v1.22.1) has no `sh` applet |
| 5 | Windows link semantics | `ln -s` copied instead of linking; `-L "link/"` always false; `cmd /c` flags mangled | MSYS `ln -s` falls back to copying; a trailing slash dereferences `-L`; MSYS2 path conversion rewrites `/c` as `C:\` | `make_dir_link` fallback chain (symlink -> `mklink /J` with `MSYS2_ARG_CONV_EXCL='*'`); strip trailing slashes before `-L` |
| 6 | `--stop-on-fail` on CI | Log showed only tests before the first failure | The full workflows pass `--stop-on-fail` | Fix the first failure; later tests never ran |
| 7 | Branch pushes trigger nothing | Pushing `interactive-ii` ran zero workflows | Full workflows trigger on PRs, tags, and `workflow_dispatch` only | Manually dispatch: `gh workflow run ci-linux.yml --ref <branch>` (repeat per target), or open a PR |
| 8 | Fast vs full test sets | New tests (0117, 2095) never ran in the fast workflows | Fast set is a fixed `only` list | Check which workflow actually covers the test before trusting a green fast run |
| 9 | Environment noise | Node 20 deprecation warnings; `GIT_CONFIG_COUNT` leakage; MSYS arg conversion toggled by the test helper | Runner-level tooling and the helper's env setup | Ignore Node warnings; remember the helper unexports MSYS path conversion so tests exercise native-git behavior |

## Adding a new lesson

When a CI-only failure is fixed, record it here before moving on. Use
this template so the next failure analysis can short-circuit:

```markdown
| N | <one-line difference> | <symptom seen> | <root cause> | <prevention> |
```

Keep the catalog ordered by how often the difference bites. If a
prevention becomes product code (a guard, a helper, a test), reference
the function or test by name so the entry stays actionable.
