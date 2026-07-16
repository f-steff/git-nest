# todo

- Deepen test coverage incrementally, one or a few commands per pass, auditing each command against its help/contract and adding the missing cases. Report and fix any bugs the new tests expose.
  - Done so far: hooks (install/uninstall/triggered) and verify.
  - Remaining audit candidates (roughly shallow or scenario-thin): restore (recovery paths, --prune/--force, partial-clone), status (--exit-code, recursive, composite/mismatch states), outdated, diff --since edge cases, log filters, freeze, config, update modes, clone modes, export formats, doctor checks, and the workflow scenarios.
- Design a conservative current-branch update workflow:
  - Consider `git-nest pull`, `git-nest update-current`, or a documented `foreach-clean -- git pull --ff-only` recipe.
  - The command should update checked-out modules on their current branches without first rewriting module state from `.gitnest`.
  - Refuse dirty worktrees, staged changes, unresolved conflicts, and ambiguous detached-HEAD states unless an explicit option says otherwise.
  - Prefer fast-forward-only behavior by default and clearly report modules that require manual merge/rebase work.
  - Do not make this a replacement for `restore` or `snapshot`. It is a working-tree convenience, not a manifest authority.
- Harden filesystem and concurrency behavior:
  - Audit path handling on case-insensitive filesystems so modules whose names differ only by case cannot corrupt each other.
  - Use canonical path checks for any operation that writes outside the root, removes files, or resolves user-provided module paths.
  - Ensure interrupted commands release locks and leave clear recovery instructions.
  - If parallel operations are introduced, serialize manifest writes and per-module metadata writes.
  - Do not use prefix string matching as a path safety check. Do not share predictable temporary filenames between simultaneous operations.
- Design machine-readable diagnostics:
  - Add JSON output where it helps automation, especially for `doctor`, `list`, and future release/install diagnostics.
  - Redact user-specific paths, usernames, remote credentials, and tokens when requested.
  - Keep text output readable for humans, but make JSON the contract for tools.
  - Do not require scripts to parse prose, tables, icons, or logo text.
- Capture release and installation hardening for later:
  - Keep install instructions shell-agnostic and avoid silently editing shell startup files.
  - If binary releases are added later, test native Windows artifacts on Windows and decide whether Windows ARM64 is supported.
  - If installer output uses color, provide a no-color path for CI, logs, and terminals without color support.
  - Do not let the installer hide required PATH or shell-profile steps behind decorative output.
- Keep subtree and git-subrepo support as deferred, explicit `absorb` source types:
  - Add them only as explicit modes such as `absorb --subtree <path> <url>` and `absorb --subrepo <path>`, never auto-detected. A Git subtree leaves no reliable on-disk marker, so it cannot be detected; a git-subrepo can be detected by `<path>/.gitrepo` but is still deferred.
  - Treat subtree absorb as equivalent to the plain-folder path plus a remembered upstream URL: forward-only, with no earlier history carried across.
  - Keep git-subrepo conversions forward-only as well, without attempting to reconstruct, rewrite, or preserve older history before the conversion point.
  - Each conversion family must have explicit terminology, tests, and documentation so users understand whether they are working with a Git submodule, Git subtree, git-subrepo, or git-nest subproject.
  - Do not merge subtree or git-subrepo behavior into the auto-detected `absorb` cases, `inline`, `detach`, `remove`, `restore`, or `snapshot`.
  - Do not hide history-loss or history-boundary semantics behind a friendly command name. The dry-run and confirmation text must say exactly what history is and is not being carried across.

# suggestions

- Use nest-related vocabulary in documentation examples to make command explanations more memorable, while keeping the actual command names literal and script-friendly.
  - Example: describe `restore` as bringing the nest back into shape, or as hatching missing checkouts, without adding `hatch` as a code alias.
  - Do not add metaphor aliases to the CLI unless there is a later explicit product decision.
- Consider `hooks-global-install` and `hooks-global-uninstall` as future opt-in helpers.
  - Pros: a global checkout hook could detect a cloned nest, install local managed hooks automatically, and print or trigger first-restore guidance. This would help users working through GUI clients where they may not remember to run `git-nest hooks-install`.
  - Cons: global Git hooks affect every repository on a machine and can surprise users, slow unrelated checkouts, or conflict with existing global hook managers.
  - How to do it: keep it explicit, reversible, and visibly installed by git-nest. The global hook should only detect `.gitnest` and delegate to local `hooks-install` or guidance; it must not store hook-installed state in `.gitnest`.
  - How not to do it: do not silently edit global Git config, do not auto-run destructive `restore`, and do not make ordinary repositories depend on git-nest being installed.

# done

- Gave every test a globally unique four-digit ID (filename prefix `test_<NNNN>_<category>_<behavior>.sh`) in category blocks stepping by 10 (command 0010+, contract 2000+, platform 3000+, symmetry 4000+, workflow 5000+), and added a `# Test:` description header to each. The runner (`.sh` and, by forwarding, `.bat`) gained commands `list` (ID + description), `only <ids>`, `except <ids>`, and `help`, plus a `--stop-on-fail` option; unknown commands, options, or IDs print help and stop. The former inline invocation-smoke check is now the real test `test_3030_platform_invocation_smoke.sh`. Docs and naming conventions updated in AGENTS.md, README.md, and docs/maintainer.md.
- Added a dedicated `verify` test (`test_command_verify_health.sh`) covering a clean pass, dirty and unmanaged-repo warnings, and missing-checkout, wrong-remote, revision-drift, and unresolvable-revision errors plus exit codes and JSON. It exposed a bug: `verify --json` always returned empty `errors`/`warnings` arrays because `verify_current` reused the global temp-file variable names `errors`/`warnings`, clobbering (and deleting) the caller's files. Refactored `verify_current` to write to caller-provided files and not print, added a `verify_report_human` wrapper, and gave `cmd_verify` uniquely named JSON variables so errors and warnings are now reported.
- Deepened hooks coverage into three tests and fixed a bug they exposed. `test_command_hooks_install.sh` covers hook-set placement, all-or-nothing unmanaged-hook refusal, recursion rejection, and auto-install on `add`; `test_command_hooks_uninstall.sh` covers managed removal, unmanaged preservation with a warning, and that removed hooks stop firing; `test_workflow_hooks_triggered.sh` drives every managed hook through real Git checkout/commit/push and asserts each effect. The utilization test uncovered that `cmd_snapshot` returned the trailing notice's status instead of the snapshot result, so the root pre-push reproducibility warning never fired inside the hook's `if ! cmd_snapshot ...`; `cmd_snapshot` now captures and returns the real result.
- Reworked conversion backups into transient, self-documenting recovery directories. `inline` and `absorb --preserve-history` create `.gitnest-recovery-<op>-<name>-<timestamp>/` with a `RECOVERY.txt` explaining restore/cleanup, ignore it on demand via the repo-local `.git/info/exclude` (never the committed `.gitignore`), and remove it on success. Interrupted conversions leave the backup with instructions, and `git-nest doctor` reports leftovers (`recovery-backup` check); `discover` prunes `.gitnest-recovery-*`. Backup-dir ignore constants were removed from the managed block.
- Managed nest-owned `.gitignore` entries in a self-healing `# BEGIN git-nest ignores` block. `init`/`repair`/`add`/`absorb`/`move`/`remove`/`inline` reconcile the block; stray nest-owned entries a user moves outside are pulled back in and deduped; user lines are preserved. `repair` prunes stale nest-owned entries (path neither managed nor present) and reports each; `doctor` warns when stale entries exist; `detach` keeps its entry for later pruning and hints at `repair`; `discover` labels a present former subproject as `detached`. Covered by a rewritten `test_contract_gitignore_hygiene.sh` and additions to `test_command_detach_keep_repo.sh`.
- Implemented the nest-membership conversion command set. `absorb` brings outer-repository files, a standalone nested repository, or a Git submodule into the nest (auto-detected), refuses already-managed paths and deeper nested repositories, and requires a remote for the files source. `inline` dissolves a subproject into outer files (the former `absorb`), `detach` keeps the checkout as a standalone ignored repository (the former `remove --keep-files`), and `remove`/`rm` deletes the checkout. `extract` and `remove --keep-files` are rejected with guidance. All four mutating verbs support `--dry-run` and `--json`/`--json-pretty`. Covered by `test_symmetry_absorb_inline.sh`, `test_command_absorb_sources.sh`, `test_command_detach_keep_repo.sh`, and updates to `test_symmetry_mv_remove.sh` and `test_platform_git_invocation.sh`.
- Implemented `git-nest discover`: a bounded, read-only scan for nested repositories and submodules not managed by `.gitnest`, with `--max-depth`, repeatable `--exclude`, a default prune list, symlink-safe traversal, kind classification, next-step suggestions, and porcelain/JSON output. Covered by `test_command_discover_unmanaged.sh`.
- Implemented `git-nest list`: a stable-order inventory of managed subprojects with URL, target branch, revision, tag, checkout state, and reproducibility, in human, porcelain, and JSON forms. Covered by `test_command_list_inventory.sh`.
- Added platform-specific installation and invocation tips for Windows, Linux, and macOS to `README.md`.
- Added a command quick-reference table to the `README.md` command section.
- Replaced the old branch/upload/finalize workflow with normal Git branch/commit/push plus `git-nest snapshot`.
- Replaced public `sync` with `restore`.
- Added `repair` so `init` creates only and existing nests are repaired explicitly.
- Added `hooks-install` and `hooks-uninstall` as symmetric hook commands.
- Added local branch memory commands: `branch-mark`, `branch-unmark`, `branch-list`, and `branch-cleanup`.
- Added nested `init --sure` confirmation behavior.
