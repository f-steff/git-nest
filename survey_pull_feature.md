# Feature design: `survey`, `absorb-all`, `pull`, and `absorb --subrepo`/`--subtree`

> **Provenance:** the original detailed design discussion for this feature set
> (an initial analysis document followed by numbered edge-case decisions) was
> never committed to the repository and was overwritten before `cmd_survey`
> was implemented. A partial backup of one earlier draft survived outside the
> repo and was restored as `survey_pull_feature__backup.md`; this file
> supersedes that backup, folding it together with the (also unrecoverable)
> integrated final answers as best they can be reconstructed. Where a detail
> could not be recovered with confidence, it is called out explicitly below
> instead of silently guessed.
>
> `survey` and its batch-absorb action were originally designed as one
> command (`survey --absorb-all`). During review, this was split into two
> commands -- `survey` (read-only) and `absorb-all` (mutating) -- to match
> git-nest's established, consistently-applied invariant that diagnostic
> commands (`status`, `outdated`, `verify`, `diff`, `log`, `list`, `discover`,
> `doctor`) never mutate anything, while mutating actions get their own
> single-purpose verb (`add`, `absorb`, `inline`, `detach`, ...) rather than a
> flag that changes what an otherwise-read-only command does. `absorb-all`
> follows the project's existing hyphenated-compound-verb convention for "the
> batch/filtered variant of X" (`hooks-install`, `branch-mark`,
> `foreach-clean`).
>
> Status at time of writing: `absorb --subrepo`, `absorb --subtree`, and the
> worktree-compatibility deliverables (W1-W4) are implemented, tested, and
> documented. `pull` is implemented (base version) but needs the edge-case
> test coverage listed below. `survey` and `absorb-all` (the merge of
> `discover` plus a batch-absorb command) are not yet implemented -- this
> document is their spec.

## 1. `git-nest survey`

### Purpose

Scan from the current working directory, detect every recognizable Git-based
structure below it, and report how to bring each one into a nest. Read-only:
`survey` never adds, syncs, registers, or otherwise mutates anything, exactly
like the `discover` command it merges and replaces (same output format,
expanded detection). Belongs in the "Inspection" help group alongside
`status`, `outdated`, `verify`, `diff`, `log`, `list`, and `doctor` -- all of
which share this same never-mutates invariant. `discover` is removed as a
live command; its dispatch entry becomes a migration error pointing at
`survey`, matching the existing pattern for other retired commands (see
`tests/test_0190_command_removed_workflow_commands.sh`, e.g. `extract` ->
"use git-nest absorb").

`survey` does not require an existing nest to run: it can scan from any
directory, nest or not, the same way `discover` does today (`discover`
requires a manifest already; whether `survey` keeps that requirement or
relaxes it is an open detail -- default to keeping `discover`'s existing
requirement unless there is a concrete reason to change it, since `survey`
is meant to be a drop-in replacement first and an enhancement second).

### Detection targets

| Target | Marker | Reliability | Absorbed by `absorb-all`? |
|--------|--------|-------------|----------------------------|
| Git submodule | `.gitmodules` entry + gitlink | High | Yes |
| Nested Git repo | `.git` directory (not a gitlink) | High | Yes |
| `git-subrepo` | `<path>/.gitrepo` file | High | **No** -- conscious action only |
| Already managed | Path listed in the current `.gitnest` | Exact | Skipped (not reported as unmanaged) |
| Subtree | No reliable marker | Not detected | No |

### Command signature

```
git-nest survey [--exclude <name>]... [--include <path>]... [--max-depth <n>]
                [--porcelain | --json | --json-pretty]
```

- `--exclude <name>`: prune any directory literally named `<name>`, found
  anywhere in the scanned tree, exactly like `discover --exclude` today.
  **Repeatable** -- each occurrence adds one name (e.g.
  `--exclude node_modules --exclude vendor`); there is no single space- or
  comma-separated list form. Takes a bare directory *name* (validated the
  same way as `discover` validates it today: simple name characters only,
  no slashes), matched by name at any depth, the same default prune list
  (`node_modules`, `vendor`, `build`, ... -- see `DISCOVER_DEFAULT_EXCLUDES`)
  still applies underneath it.
- `--include <path>` (new): restrict the scan to this *path* (and everything
  beneath it) instead of the whole tree from cwd. **Repeatable** -- each
  occurrence adds one path to the included set, same convention as
  `--exclude`; e.g. `--include vendor --include third_party/libs` scans only
  those two subtrees. If `--include` is never given, behavior is unchanged
  (scan everything from cwd, as today). Multiple overlapping include paths
  are harmless (the row-collection step already dedupes by path). Unlike
  `--exclude`, this takes a relative *path*, which may contain `/`: validated
  the same way as other path arguments elsewhere in git-nest (forward
  slashes only, relative, no `..` escape) and refused with a clear error if
  the path does not exist as a directory (most likely a typo). `--exclude`
  still prunes matching names within an included path (e.g.
  `--include vendor --exclude vendor/already-reviewed` scans under `vendor/`
  but skips that one subdirectory by name). `--max-depth` still counts from
  cwd, not from each included path, so an include path already deeper than
  `--max-depth` yields nothing -- an intentional, unsurprising interaction
  since each flag keeps its own literal meaning.
- `--max-depth`: same semantics as `discover` today (bounded traversal depth,
  default 4).
- `--porcelain` / `--json` / `--json-pretty`: same 7-column row schema and
  JSON envelope `discover` already emits.

### Output format

Matches the current `discover` format; `G` is the one new code:

```
S  libs/foo          submodule    run git-nest absorb libs/foo (init the submodule first if not checked out)
R  vendor/bar        nested-repo  run git-nest absorb vendor/bar to manage it
G  tools/baz         subrepo      run git-nest absorb --subrepo tools/baz (not absorbed by absorb-all)
N  nested/proj       nest-root    nested nest; run git-nest inside it or use --recursive commands
D  old/thing         detached     detached former subproject; git-nest absorb old/thing to re-manage, or move/remove it and run git-nest repair
```

Existing codes carried over unchanged from `discover_classify_row`:
`S` submodule, `R` nested-repo, `N` nest-root, `D` detached. New: `G` subrepo.

### Detection algorithm

```
1. cwd = pwd -P
2. Resolve the scan roots: cwd itself, or the union of --include paths if
   any were given
3. Scan cwd for .gitmodules -> extract every [submodule "path"] entry
4. Scan each scan root (bounded by --max-depth counted from cwd, pruned by
   --exclude) for .git entries and .gitrepo files, exactly as discover_scan
   does today
5. Classify each hit, stopping at (never descending past) the first
   boundary found along a given path:
   - Already listed in .gitnest -> skip (it is the subproject's own checkout)
   - .gitmodules entry / gitlink .git file -> submodule (S)
   - Nest-owned .gitignore block entry present -> detached (D)
   - Has its own .gitnest -> nest-root (N)
   - .gitrepo file -> subrepo (G)
   - Plain .git directory -> nested-repo (R)
6. Do not report anything found underneath a boundary already classified
   above (see the boundary-enforcement rule in section 1a)
7. Sort output by path for stable, deterministic rows
8. Print/emit rows (human, --porcelain, or --json/--json-pretty)
```

`absorb-all` (section 2) reuses this exact scanning/classification logic
rather than reimplementing it, so `survey` and `absorb-all` always agree on
what is out there.

### 1a. Boundary enforcement (critical, must be tested explicitly)

Nested-repository, submodule, subrepo, and subtree boundaries are
**impossible to cross by design**: once a path is inside one of these, it
belongs to that inner repository exclusively, and the outer nest must never
see, scan, report, or act on anything underneath it. Concretely:

- A nested Git repository found inside a submodule, inside a subrepo, or
  inside a subtree-shaped plain directory is **not** reported by `survey` --
  only the outer boundary (the submodule/subrepo/subtree-looking directory
  itself) is visible. The inner repository is that boundary's own concern,
  not the outer nest's.
- `absorb-all` must never attempt to absorb something found underneath a
  boundary it already classified, even if that inner thing would otherwise
  look absorbable in isolation.
- This must be covered by a dedicated test: construct a nested repo inside a
  submodule, inside a subrepo, and inside a subtree-shaped directory, and
  assert that plain `survey` and `absorb-all` never surface or act on the
  inner path -- only the outer boundary appears in output.

### Detection edge case decisions

| # | Case | Decision |
|---|------|----------|
| 1 | Submodule not checked out | Reported with a note to run `git submodule update --init <path>` first, then re-run `survey`. `survey` completes; absorbing it (via `absorb` or `absorb-all`) is not possible until the submodule is initialized. |
| 2 | Nested repo has no origin | Reported with the exact command to set one: `git -C <path> remote add origin <url>`. `survey` completes; absorbing it is not possible until origin is set (matches `absorb`'s existing "has no origin remote" guard). |
| 3 | Conflicting structures at the same path | Deduplicate by path. A submodule entry takes priority over a plain nested-repo classification at the same path. First detection wins. |
| 4 | Nested repo inside a submodule (or subrepo, or subtree) | Impossible by design -- see section 1a. Any path inside a subproject/submodule/subrepo/subtree is off-limits to the outer nest's survey/absorb. |
| 5 | `.gitmodules` cleanup after absorbing a submodule | Already handled by `absorb`'s existing submodule path; `survey` needs no extra action. |
| 6 | Output format | Match the current `discover` format exactly (same 7-column rows, same JSON envelope); `survey` replaces `discover`. |
| 7 | `--include` path does not exist | Refuse with a clear error before scanning (most likely a typo), rather than silently scanning nothing. |
| 8 | `--include` and `--exclude` together | `--exclude` still prunes matching names within the `--include`-narrowed scan; the two combine rather than one overriding the other. |

## 2. `git-nest absorb-all`

### Purpose

Run `survey`'s scan internally, then absorb every detected submodule and
nested repo in one step. Belongs in the "Export and nest membership" help
group alongside `export`, `absorb`, and `inline` -- the mutating family --
never the "Inspection" group `survey` lives in. Subrepos (`G`) and subtrees
are always excluded from `absorb-all`: converting them touches actual
tracked files and/or discards `.gitrepo` metadata, so they remain a
conscious, single-target action via `absorb --subrepo`/`absorb --subtree`
only.

### Command signature

```
git-nest absorb-all [--sure] [--force-partial] [--dry-run]
                    [--exclude <name>]... [--include <path>]... [--max-depth <n>]
                    [--json | --json-pretty]
```

- `--exclude`, `--include`, `--max-depth`: identical semantics to `survey`
  (section 1) -- `absorb-all` performs the same scan `survey` would with the
  same flags, then acts on the S/R rows it finds.
- `--sure`: confirms extending the current nest when `absorb-all` is run
  from inside an existing one, or confirms running `init` on the caller's
  behalf when the current directory is not yet a nest. Without `--sure`,
  either situation fails with guidance. `--sure` never creates a *nested*
  nest -- that remains `init --sure`'s job, run explicitly by the operator
  inside the inner directory.
- `--force-partial`: skip the default rollback-on-failure behavior (see
  edge case 3 below) and leave already-absorbed items in place. Documented
  as a power-user, risky option: it deliberately leaves the nest in a
  partially-converted state.
- `--dry-run`: print the planned `init`/`absorb` actions without writing
  anything.
- `--json` / `--json-pretty`: machine-readable output, same envelope style
  as `absorb`'s own JSON output, one row per absorbed (or planned) item.

### Algorithm

```
1. If CWD is not itself a Git repository, explain that it must become one
   (git init) before absorb-all can proceed; stop here
2. If CWD is not yet a git-nest workspace: without --sure, refuse with
   guidance to rerun with --sure (mirrors init --sure's existing precedent);
   with --sure, run init on the caller's behalf
3. If CWD is already inside an existing nest (as a subproject or a nested
   nest) in a way that would make absorb-all ambiguous about which nest it
   extends: without --sure, refuse with guidance; with --sure, extend the
   current nest (never create a nested nest)
4. Run survey's scan (section 1's algorithm), honoring --exclude, --include,
   --max-depth exactly as survey would
5. Filter to S (submodule) and R (nested-repo) rows only; G (subrepo) and
   anything else are never touched
6. Sort candidates by path depth descending (deepest first) so a nested
   repo is absorbed before any repo containing it
7. For each candidate, in order: run the equivalent of git-nest absorb
   <path>, creating its own recovery backup as absorb already does
8. If any absorb in the batch fails: by default, roll back every absorb
   already performed earlier in this same run, explain what failed and why,
   state that the batch was rolled back, and suggest --force-partial for the
   case where the partial state is acceptable. With --force-partial, skip
   rollback and leave successfully-absorbed items in place, reporting
   exactly which ones succeeded and which failed
9. Report a summary (human, --json, or --json-pretty) of what was absorbed,
   skipped (already excluded types), and failed
```

### Edge case decisions

| # | Case | Decision |
|---|------|----------|
| 1 | CWD not in a Git repo | Refuse; explain the CWD must become a Git repo (`git init`) before `absorb-all` can run. Contrast with plain `survey`, which still works from a non-repo directory since it never writes anything. |
| 2 | CWD not yet a nest, or inside an existing nest | Fails unless `--sure` is given. `--sure` runs `init` on the caller's behalf if needed, or extends the current nest if run from inside one; it never creates a nested nest. |
| 3 | Error recovery mid-batch | Each absorb creates its own recovery backup (the existing `begin_recovery_backup`/`end_recovery_backup` mechanism). On any failure partway through the batch: roll back every absorb performed earlier in the same run, explain what failed and how to fix it, and state that the batch was rolled back. Suggest `--force-partial` for the case where the partial state is acceptable; document it as a power-user option that can leave the workspace in a mixed state. |
| 4 | `.gitrepo`/subtree exclusion | Never absorbed by `absorb-all`, regardless of flags; always requires the explicit `absorb --subrepo`/`absorb --subtree` invocation. |
| 5 | JSON output | Yes -- `--json`/`--json-pretty`, one row per absorbed (or planned, under `--dry-run`) item, matching `absorb`'s own JSON row shape. |

## 3. New subprojects must be created entirely inside the nest's own repository

The boundary rule in section 1a is about *reading* (survey must not see
across a boundary). Its necessary counterpart is about *writing*: no command
that creates a new managed subproject (`add`, `absorb` in any of its forms,
`absorb-all`) may ever place that subproject at a path that already belongs
to a different repository -- another managed subproject's checkout, or (see
section 4) a different nest's own root.

**A real, active bug was found and fixed while implementing this section**
(not merely a hypothetical edge case): `assert_path_not_inside_nested_project`
built its boundary list with `manifest_subprojects | while IFS= read -r
boundary; do ... precondition_error ...; done`. Piping into a `while` loop
runs the loop in a subshell, so `precondition_error`'s `exit` only terminated
that subshell -- the calling command (e.g. `add`) then silently continued
past the guard as if it had passed. Verified directly: `git-nest add <url>
libs/foo/brandnew`, where `libs/foo` was already a managed subproject, printed
nothing wrong and actually cloned a brand-new Git repository *inside*
`libs/foo`'s own working tree, invisible to the outer `.gitnest`, corrupting
the boundary the check was supposed to enforce. It only happened to fail
afterward for an unrelated reason (an empty seed remote), which is what let
this survive undetected. The same broken pattern also existed in
`stage_export_tree` (used by `export`): a missing subproject checkout would
print the right error but let `export` continue and silently produce an
incomplete archive.

Additionally, `assert_path_not_inside_nested_project` only treated a
subproject as a boundary when it was itself a nested nest (`[ -f
"$boundary/$MANIFEST_FILE" ]`); an ordinary subproject checkout (no nested
`.gitnest`) was not recognized as a boundary at all. And there was no
opposite check: nothing refused a candidate path that itself *contained* an
existing plain subproject (e.g. `absorb libs` when `libs/foo` is already a
managed subproject) -- only the narrower case of containing a nested
`.gitnest` file was caught.

**Fix applied** (`bin/lib/git-nest-manifest.sh`):

- `assert_path_not_inside_nested_project` now reads the subproject list from
  a temp file and iterates with `while ... done <file` (redirection, not a
  pipe) so `precondition_error` actually terminates the command. It now
  treats every existing subproject as a boundary, not only nested nests, and
  reports a differentiated message: "is inside nested project X; run
  git-nest from X instead" when X is itself a nest, or "is inside managed
  subproject X; that path belongs to X's own repository, not this nest"
  otherwise.
- `assert_path_not_containing_nested_project` gained a second check (same
  temp-file pattern): after its existing check for a nested `.gitnest` file
  underneath the candidate, it also refuses when any existing managed
  subproject sits underneath the candidate, with "X contains managed
  subproject Y; converting X would swallow that subproject's separate
  checkout".
- `stage_export_tree` (`bin/lib/git-nest-conversion.sh`) was fixed the same
  way (temp file plus redirection) so a missing-subproject error during
  `export` actually aborts instead of producing a silently incomplete
  archive.

These two functions are shared by `add`, `remove`, `move`/`mv`, `config`,
`update`, `freeze`, `absorb` (all sources, including `--subrepo`/`--subtree`),
`inline`, and `detach`, so the fix applies everywhere a path is validated
against existing boundaries, not just in `absorb`. Regression coverage was
added to `tests/test_2060_contract_path_safety.sh`: a path inside a plain
managed subproject, a path inside a nested-nest subproject (the differentiated
message), a path that contains a plain managed subproject, and a path that
contains a nested nest's own `.gitnest` (the pre-existing, still-separate
check) are all exercised.

`survey`/`absorb-all` must rely on these same, now-corrected functions rather
than reimplementing boundary checks independently, so this class of bug
cannot resurface in the new commands.

## 4. `init`/`init --sure` creating a nested nest that overlaps a deeper subproject

A related but distinct edge case surfaced while reasoning about the fixes in
section 3, specific to `init --sure` rather than `add`/`absorb`: **not yet
fixed, needs further design** before `absorb-all` (which can trigger `init`)
can be considered complete.

**Scenario:** the outer nest at `nest/` has a subproject registered at
`a/b/c/d`. Someone runs `git-nest init --sure` at `nest/a/b` to create a
nested nest there. The new nest's root (`a/b`) would then sit strictly
between the outer nest root and the outer nest's already-managed subproject
path `a/b/c/d` -- i.e. the new nest's own directory tree would contain a path
that is still owned and tracked by the *outer* nest's manifest, not the new
inner one. This is the mirror image of section 3: instead of a new
subproject being created inside an existing one, a new *nest* is created
around (as an ancestor of) an existing subproject it does not own.

**Required behavior:** `init`/`init --sure` must detect this conflict before
creating anything -- walk the new root's subtree for any path already
registered as a subproject by an ancestor nest -- and refuse with a specific
error identifying which outer nest owns the conflicting subproject(s) and
their path(s).

**Proposed direction (not decided -- needs design):** an `--adopt` flag
(exact name open) on `init` that, when this conflict is detected, moves the
conflicting subproject registration(s) out of the outer nest's manifest and
into the newly created inner nest's manifest, rewriting each moved entry's
path relative to the new root (e.g. `a/b/c/d` in the outer manifest becomes
`c/d` in the inner manifest). Open questions to resolve before building this:

- Multiple conflicting subprojects under the new root must all be handled in
  one pass, not just the first one found.
- What happens if a conflicting subproject's working tree is dirty, or its
  checkout is missing/stale, at adoption time -- refuse, warn, or proceed
  anyway?
- The outer nest's `.gitignore` managed-block entry and the new inner nest's
  managed-block entry both need updating (remove from outer, add to inner)
  as part of the same atomic operation.
- Needs its own recovery-backup/rollback story if the move fails partway,
  consistent with how `absorb`/`inline`/`move` already protect against
  partial failure.
- Must support `--dry-run` and report exactly what would move.
- Needs a dedicated test replicating the exact scenario above (outer nest,
  deep subproject, nested `init --sure --adopt` at an intermediate path).

This is relevant to `absorb-all` because it can invoke `init` on the
caller's behalf (section 2, edge case 2): if `absorb-all` is ever run from a
directory that would create this overlap, it must surface the same refusal
(and, once built, the same `--adopt` option) rather than silently creating
an inconsistent nested nest.

## 5. Worktree compatibility

**Status: implemented.** git-nest is already worktree-transparent (each
worktree has its own `.gitnest`, its own subproject checkouts, its own lock
file, and Git's own `git rev-parse --git-path`-resolved, worktree-aware
materialized-state path), so no implementation change was needed. Delivered:

- `docs/technical_docs.md` -- Worktree Compatibility section.
- `skills/git-nest/SKILL.md` -- Worktrees subsection.
- `tests/test_5050_workflow_worktree.sh` -- worktree isolation test,
  including a materialized-state path assertion.

No guard against running git-nest commands from a linked worktree was added
(none is needed: each worktree resolves its own paths correctly), and lock
conflicts across worktrees were not a concern since each worktree's
`.gitnest.lock` is scoped to that worktree's own root.

## 6. `absorb --subrepo` / `absorb --subtree`

**Status: implemented and tested** (see `bin/lib/git-nest-conversion.sh`:
`gitrepo_get`, `absorb_subrepo`, `absorb_subtree`; tests
`tests/test_0260_command_option_absorb_subrepo.sh` and
`tests/test_0270_command_option_absorb_subtree.sh`).

### Purpose

Two explicit `absorb` source types for structures neither `survey` nor
`absorb-all` can safely auto-convert. The flags make the action conscious:
both conversions touch actual tracked files in the outer repository, unlike
submodule absorb (which only removes `.gitmodules` wiring) or nested-repo
absorb (which records an existing checkout as-is).

### Command signature

```
git-nest absorb --subrepo <path> [<remote-url>] [--force] [--dry-run] [--json|--json-pretty]
git-nest absorb --subtree <path> <remote-url> [--branch <name>] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]
```

### Design

| Aspect | `--subrepo` | `--subtree` |
|--------|-------------|-------------|
| Marker | `<path>/.gitrepo` | None (no standard marker) |
| Detectable by `survey` | Yes -- `.gitrepo` file (code `G`) | No -- the caller must know |
| Absorbed by `absorb-all` | No | No |
| Remote URL | Read from `.gitrepo`; explicit `<remote-url>` overrides it | Required as a CLI argument |
| History | Forward-only, no reconstruction; `.gitrepo` removed | Forward-only, single fresh commit |
| Supports | `--dry-run`, `--json`/`--json-pretty`, recovery backup, dirty-path guards | Same |

## 7. `git-nest pull`

**Status: base implementation done** (`cmd_pull`/`pull_current`/
`pull_recursive` in `bin/lib/git-nest-commands.sh`), including the detailed
per-category summary with fix-it suggestions. Still needed: dedicated tests
for detached HEAD, no upstream, diverged, `--sure`, `--recursive` into
nested nests, `--dry-run`, and `--json`.

### Purpose

Update clean subprojects to their latest upstream commits and record the new
revisions in `.gitnest`. Conceptually equivalent to
`foreach-clean --continue-on-error -- git pull --ff-only` followed by
`snapshot`, but as a structured command that reports per-subproject outcomes
instead of failing the whole run on the first error. The `foreach` recipe
stays documented as a lightweight example alternative.

### Command signature

```
git-nest pull [--recursive] [--sure] [--no-fetch] [--dry-run] [--json | --json-pretty]
```

- `--recursive`: also pull inside nested nests (subprojects that are
  themselves `.gitnest` workspaces). Does not by itself pull the outer root.
- `--sure`: also pull the nest root itself (default: subprojects only).
- `--no-fetch`: use local refs only (no network access).
- `--dry-run`: show planned actions without writing.
- `--json` / `--json-pretty`: machine-readable output.

### Algorithm

```
1. Require a nest (enter_project_root_required)
2. Select clean, checked-out subprojects
3. For each:
   a. Detached HEAD -> skip, warn, suggest switching to a branch
   b. No upstream tracking -> skip, warn, suggest
      git branch --set-upstream-to=origin/<branch>
   c. git pull --ff-only
   d. Non-fast-forward (diverged) -> report "diverged", suggest merge/rebase,
      never force
   e. Network/fetch error -> report "failed", continue with the rest
4. If --sure: git pull --ff-only on the nest root itself
5. If --recursive: recurse into nested nests, reporting and continuing on
   per-nest error
6. Snapshot successfully pulled subprojects (without --strict; a subproject
   that cannot be snapshotted is skipped and reported, not fatal)
7. Report a summary listing the actual subproject paths in each category
   (pulled, skipped/detached, skipped/no-upstream, diverged, failed), each
   with a concrete fix-it command -- not just counts
```

### Edge case decisions

| # | Case | Decision |
|---|------|----------|
| 1 | Pull the nest root? | Only subprojects by default. `--sure` also pulls the nest root. `--recursive` handles nested nests, not the root. |
| 2 | Detached HEAD | Skip with a warning; suggest switching to a branch. |
| 3 | No upstream tracking | Skip with a warning; suggest `git branch --set-upstream-to=origin/<branch>`. |
| 4 | Non-fast-forward (diverged) | Report as "diverged" and continue; suggest manual merge/rebase; never force. |
| 5 | `snapshot` finds issues after pulling | Run without `--strict`; a subproject that cannot be snapshotted is skipped and reported, not fatal. |
| 6 | `--recursive` into nested nests | Recurse into each; on error, report and continue; include fix suggestions where possible. |
| 7 | Network errors | Continue by default; report which subprojects failed to fetch. |
| 8 | `--dry-run` | Show what would be pulled/skipped and why; no fetch, no modifications. |
| 9 | JSON output | Yes -- `pull`, `survey`, and `absorb-all` all support `--json`/`--json-pretty`. |

## 8. Implementation order

1. `absorb --subrepo` -- done.
2. `absorb --subtree` -- done.
3. Worktree deliverables (W1-W4) -- done.
4. `pull` base implementation -- done; edge-case tests remain.
5. `survey` detection-only mode, merging `discover`, including `--include` --
   not started.
6. `absorb-all` execution command with rollback -- not started.

## 9. Risk assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| `survey` detects something it should not | User absorbs the wrong path | Low | Detection-only by default; `absorb-all` is a separate, explicit, opt-in command |
| `survey` misses something | User does not convert everything | Medium | Document the exclusion list; `--exclude`/`--include` overrides |
| `absorb-all` leaves the workspace half-migrated | Confused user | Medium | Rollback on error by default; clear per-item summary |
| `pull` creates merge commits | Unexpected history | Very low | `--ff-only` enforced by Git itself |
| Subrepo/subtree absorb touches the wrong files | Lost history | Low | Recovery backup created before every conversion |

## Implementation status (verified against files on disk)

- **Done, tested, documented:** `absorb --subrepo`, `absorb --subtree` (see
  section 6); worktree compatibility deliverables W1-W4 (see section 5).
- **Done (base implementation), needs edge-case tests:** `pull` (see
  section 7's status note).
- **Not started:** `cmd_survey` and `cmd_absorb_all` in
  `bin/lib/git-nest-doctor.sh` (`discover` is still the live command,
  unchanged). Remaining work:
  - Merge `discover_scan`/`discover_classify_row` logic into `survey`'s
    detection mode, adding the `G` (subrepo) code, `--include`, and the
    boundary-stop rule from section 1a.
  - Implement `absorb-all` as its own command: its own option parsing,
    reusing `survey`'s scan, `--sure`/`--force-partial`/rollback per
    section 2.
  - Wire dispatch and help/completions for both new commands: `survey` ->
    `cmd_survey` (Inspection group); `absorb-all` -> `cmd_absorb_all`
    (Export and nest membership group); `discover` -> usage error with
    migration guidance.
  - Update `docs/command-behavior-contract.md`, `docs/technical_docs.md`,
    `skills/git-nest/SKILL.md`, and `schemas/git-nest-output-v1.schema.json`.
  - Rewrite `tests/test_0080_command_discover_unmanaged.sh` to test `survey`
    instead (and add a case asserting `discover` now errors with migration
    guidance).
  - Add the boundary-enforcement test described in section 1a.
