# Feature Analysis: `survey`, `absorb --subrepo/--subtree`, and `pull`

## 1. `git-nest survey`

### Purpose

Scan from the current working directory (no nest required), detect every recognizable Git-based structure below it, and report how to bring them into a nest. Merges and replaces the existing `discover` command — same output format, expanded detection.

### Detection targets

| Target | Marker | Reliability | In `--absorb-all`? |
|--------|--------|-------------|--------------------|
| Git submodule | `.gitmodules` file + `.git` gitlink file | High | Yes |
| Nested Git repo | `.git` directory (not a gitlink) | High | Yes |
| `git-subrepo` | `<path>/.gitrepo` file | High | **No** — conscious action only |
| Already managed | Path listed in existing `.gitnest` | Exact | Skipped |
| Subtrees | No reliable marker | Excluded | No |

### Command signature

```
git-nest survey [--absorb-all] [--sure] [--dry-run]
                [--exclude <name>...] [--max-depth <n>]
                [--json | --json-pretty]
```

- `--absorb-all`: run `init` (if needed), then `absorb` for each detected submodule and nested repo. Fails unless `--sure` is provided when inside an existing nest. Subrepos and subtrees are excluded — they must be absorbed manually.
- `--sure`: confirms extending an existing nest when `--absorb-all` is used inside one.
- `--dry-run`: print planned actions without writing.
- `--exclude`, `--max-depth`: same semantics as `discover`.
- `--json` / `--json-pretty`: machine-readable output in same schema as `discover`.

### Output format

Matches the current `discover` format (merged — `survey` replaces `discover`):

```
S  libs/foo          submodule    run: git submodule update --init libs/foo, then git-nest absorb libs/foo
R  vendor/bar        nested-repo  git-nest absorb vendor/bar
G  tools/baz         subrepo      git-nest absorb --subrepo tools/baz  (not included in --absorb-all)
```

### Detection algorithm

```
1. cwd = pwd -P
2. Scan cwd for .gitmodules → extract all [submodule "path"] entries
3. Scan cwd recursively for .git directories and .gitrepo files
4. Classify each hit:
   - .gitmodules entry → submodule (S)
   - .git file with "gitdir:" prefix → submodule checkout (S, skip if already in .gitmodules)
   - .git directory → nested repo (R)
   - .gitrepo file → subrepo (G)
5. Check if CWD would become a Git repo: if not already one, explain that git-nest needs one
6. Check if already inside a nest: if yes and --absorb-all without --sure, fail gracefully
7. Sort by path depth descending (deepest first)
8. Output or execute
```

### Edge case decisions

| # | Case | Decision |
|---|------|----------|
| Q1 | CWD not in a Git repo | Survey works. Output explains that the CWD must become a Git repo (`git init`) before `init`/`absorb` can run. |
| Q2 | Inside an existing nest | Survey detects, shows unmanaged items with absorb commands. `--absorb-all` fails unless `--sure` is given. `--sure` extends the current nest (does NOT create a nested nest). Document how to create nested nests explicitly. |
| Q3 | Submodule not checked out | Reported with a note: "run `git submodule update --init <path>` first, then re-run survey". Survey completes. Absorb not possible until initialized. |
| Q4 | Nested repo has no origin | Reported with the exact command to set it: `git -C <path> remote add origin <url>`. Survey completes, absorb not possible until origin is set. |
| Q5 | Conflicting structures at same path | Deduplicate by path. Submodules take priority over nested repos. First detection wins. Document edge cases. |
| Q6 | Nested repo inside a submodule | **Impossible by design** — nest subprojects must only exist in their own filesystem. Any path inside a subproject/submodule/subrepo/subtree is off-limits to the outer nest. Those inner paths can contain their own nested nest. Must be documented and tested. |
| Q7 | `--absorb-all` error recovery | Each absorb creates a recovery backup. On failure: roll back, explain what failed, how to fix, and that the absorb was rolled back. Suggest `--force-partial` if the user wants to retry without rollback (for cases where the partial state is acceptable). `--force-partial` skips the rollback backup and leaves successfully-absorbed items in place. Document the flag carefully — it is a power-user option that can leave the workspace in a mixed state. |
| Q8 | `.gitmodules` cleanup | Handled by `absorb` — no survey action needed. |
| Q9 | Output format | Match current `discover` format. `survey` replaces `discover` (old name redirects with guidance). |

---

## 2. Worktree compatibility

### Background

Git worktrees (`git worktree add`) allow multiple working trees from the same repository. Each worktree has its own working directory, index, and private Git metadata under `.git/worktrees/<name>/`. The object database and refs are shared.

### How git-nest interacts with worktrees

| Component | Main worktree | Linked worktree | Shared? |
|-----------|---------------|-----------------|---------|
| `.gitnest` manifest | In worktree root | In worktree root | No — each worktree checks out its own branch |
| Subproject checkouts | `libs/foo/` | `libs/foo/` (independent clone) | No |
| `.gitnest.lock` | In worktree root | In worktree root | No |
| Materialized state | `.git/git-nest/subprojects` | `.git/worktrees/<name>/git-nest/subprojects` | No — `git rev-parse --git-path` is worktree-aware |
| `.gitignore` / `.gitattributes` | In worktree root | In worktree root | No |

**Conclusion: git-nest is already worktree-transparent.** No implementation changes needed.

### Deliverables

| # | Deliverable | Type |
|---|-------------|------|
| W1 | `docs/technical_docs.md` — Worktree Compatibility section | Documentation |
| W2 | `skills/git-nest/SKILL.md` — Worktrees subsection | Documentation |
| W3 | `test_5050_workflow_worktree.sh` — worktree isolation test | Test |
| W4 | Materialized-state path assertion (inside W3) | Test assertion |

### Decisions (previously open questions)

- **Q11 (worktree guard)**: No guard needed. Keep without guards.
- **Q12 (lock conflict across worktrees)**: Each worktree has its own `.gitnest` on its own branch — no shared state. A test will verify this explicitly.

---

## 3. `absorb --subrepo` / `absorb --subtree` flags

### Purpose

Two explicit absorb source types for structures that `survey` cannot safely auto-convert. The flags make the action conscious — absorbs that touch actual code files in the repository require explicit opt-in.

### Command signature

```
git-nest absorb --subrepo <path> [<remote-url>]
git-nest absorb --subtree <path> <remote-url>
```

### Design

| Aspect | `--subrepo` | `--subtree` |
|--------|-------------|-------------|
| Marker | `<path>/.gitrepo` | None (no standard marker) |
| Detectable by `survey` | Yes — `.gitrepo` file | No — user must know |
| Included in `survey --absorb-all` | **No** | **No** |
| Remote URL | Read from `.gitrepo` | Required as CLI argument |
| History | Forward-only, no reconstruction | Forward-only, single-commit snapshot |
| Must support | `--dry-run`, `--json`/`--json-pretty`, recovery backup | Same |

### Rationale

Both subrepo and subtree absorbs modify actual tracked files in the outer repository. This is fundamentally different from submodule absorb (which only removes wiring from `.gitmodules`) or nested repo absorb (which records an existing checkout).

---

## 4. `git-nest pull`

### Purpose

Update all clean subprojects to their latest upstream commits and record the new revisions in `.gitnest`. Equivalent to: `foreach-clean --continue-on-error -- git pull --ff-only` then `snapshot`. The foreach recipe stays documented as an example.

### Command signature

```
git-nest pull [--recursive] [--sure] [--no-fetch] [--dry-run] [--json | --json-pretty]
```

- `--recursive`: also pull in nested nests.
- `--sure`: also pull the nest root itself (default: only subprojects).
- `--no-fetch`: use local refs only.
- `--dry-run`: show planned actions without writing.
- `--json` / `--json-pretty`: machine-readable output.

### Algorithm

```
1. Require a nest (enter_project_root_required)
2. Select clean subprojects (foreach-clean)
3. For each clean subproject:
   a. Skip if detached HEAD → report "skipped (detached)"
   b. Skip if no upstream tracking → report "skipped (no upstream)", suggest --set-upstream-to
   c. git pull --ff-only
   d. If non-fast-forward → report "diverged", suggest merge/rebase
   e. If network error → report "failed", continue
4. If --sure: git pull --ff-only on the nest root itself
5. If --recursive: recurse into nested nests
6. Snapshot successfully pulled subprojects
7. Report summary table (pulled, skipped, diverged, failed)
```

### Edge case decisions

| # | Case | Decision |
|---|------|----------|
| Q10 | Pull nest root? | Only subprojects by default. `--sure` also pulls the nest root. `--recursive` handles nested nests, NOT the root. |
| Q11-2 | Detached HEAD | Skip with warning. Suggest switching to a branch. |
| Q12-2 | No upstream tracking | Skip with warning. Suggest `git branch --set-upstream-to=origin/<branch>`. |
| Q13 | Non-fast-forward (diverged) | Report as "diverged" and continue. Suggest manual merge/rebase. Never force. |
| Q14 | Snapshot finds issues | Run `snapshot` without `--strict`. If a subproject can't be snapshotted, skip it and report. |
| Q15 | `--recursive` nested nests | Recurse into each nested nest. On error: report and continue. Output fix suggestions when possible. |
| Q16 | Network errors | Continue on error by default. Errors covered by recorded rollback if applicable. |
| Q17 | `--dry-run` | Show what would be pulled, skipped, and why. No fetch, no modifications. |
| Q18 | JSON output | Yes — both `survey` and `pull` support `--json`/`--json-pretty`. |

---

## 5. Implementation order

1. **`absorb --subrepo`** — detect and absorb subrepos
2. **`absorb --subtree`** — absorb subtrees (requires remote URL)
3. **`survey`** — detection-only mode, merges `discover`
4. **`survey --absorb-all`** — execution mode with rollback
5. **`pull`** — convenience command
6. **Worktree deliverables** (W1–W4) — documentation and tests (can be done in parallel with 3–5)

## 6. Risk assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| `survey` detects something it shouldn't | User absorbs wrong path | Low | Dry-run first, explicit `--absorb-all` |
| `survey` misses something | User doesn't convert everything | Medium | Document exclusion list, `--exclude` override |
| `--absorb-all` leaves workspace half-migrated | Confused user | Medium | Rollback on error, print summary |
| `pull` creates merge commits | Unexpected history | Very low | `--ff-only` enforced by Git |
| Subrepo/subtree absorb touches wrong files | Lost history | Low | Recovery backup before conversion |
