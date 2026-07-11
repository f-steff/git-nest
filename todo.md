# todo

- Design Git submodule conversion commands:
  - `git-nest submodules`: list Git submodules from `.gitmodules`, showing path, URL, branch when present, and whether the submodule checkout exists.
  - `git-nest adopt-submodule <path>`: convert an existing Git submodule into a git-nest subproject at the same path.
  - `git-nest eject-submodule <path>`: convert a git-nest subproject back into a Git submodule.
  - The conversion commands must be explicit, reversible by design, and dry-run friendly. They must explain which files and Git metadata will change before changing them.
  - Do not silently rewrite `.gitmodules`, `.git/config`, `.gitnest`, or nested repository state. Do not treat subtree conversion as the same problem as submodule conversion.
- Design unmanaged nested repository discovery:
  - Add either `git-nest discover` or an explicit `git-nest status --unmanaged` mode that scans for nested `.git` repositories not listed in `.gitnest`.
  - Support bounded scans with a depth option and exclude patterns for directories such as `node_modules`, `vendor`, build output, caches, and generated dependency folders.
  - Report enough context to act on the result: path, whether it is inside an existing module, whether it is already a nest root, and a suggested next command when safe.
  - Keep this as discovery only. Do not auto-add, auto-sync, or auto-register repositories with IDEs.
  - Do not scan unbounded directory trees by default, and do not follow symlinks without an explicit decision and tests.
- Design a public module listing command:
  - Add `git-nest list` to list `.gitnest` modules in a stable order.
  - Include script-friendly output and JSON output so callers do not have to parse human `status` text.
  - Include at least path, URL, target branch, revision, tag, current checkout state, and reproducibility status.
  - Keep `status` focused on workspace health. Do not make scripts depend on decorative or human-oriented status output.
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
- Keep subtree and git-subrepo support as separate future designs:
  - Subtree import/export may be useful, but it changes repository content and history semantics in a way that is different from nest modules and Git submodules.
  - Git-subrepo import/export may also be useful for users who already rely on git-subrepo-style embedded repositories.
  - Keep these conversions simple: support conversion from the chosen point forward only, without attempting to reconstruct, rewrite, or preserve older history before the conversion point.
  - Each conversion family must have explicit terminology, tests, and documentation so users understand whether they are working with a Git submodule, Git subtree, git-subrepo, or git-nest module.
  - Do not merge subtree or git-subrepo behavior into `adopt-submodule`, `eject-submodule`, `restore`, or `snapshot`.
  - Do not hide history-loss or history-boundary semantics behind a friendly command name. The dry-run and confirmation text must say exactly what history is and is not being carried across.

# suggestions

- Revisit the names of the outer-repo conversion commands from the nest's point of view.
  - Current issue: `extract` and `absorb` describe what happens to files from the outer repository's mechanical perspective, but they do not read clearly from the nest's perspective.
  - Possible direction: rename current `extract` to something like `adopt` because the nest is adding a directory as a managed subproject.
  - Possible direction: rename current `absorb` to something like `inline` because the nest stops managing the subproject and the outer repository tracks the files directly.
  - Pros: nest-view names make direction easier to understand and reduce the risk of users running the opposite conversion.
  - Cons: metaphor names can be less obvious in scripts and may require extra help text for users who think in Git mechanics.
  - How to do it: keep old names as rejected aliases with clear guidance during the unreleased redesign window, update tests and docs together, and make dry-run output state exactly whether the path is being added to or removed from the nest.
  - How not to do it: do not use `expel` for the current `absorb` behavior unless the command leaves a standalone repository outside the nest. `expel` sounds like "remove from the nest but keep as a repository", which is closer to `remove --keep-files` or a future detach command than to folding files into the outer repository.
- Use nest-related vocabulary in documentation examples to make command explanations more memorable, while keeping the actual command names literal and script-friendly.
  - Example: describe `restore` as bringing the nest back into shape, or as hatching missing checkouts, without adding `hatch` as a code alias.
  - Do not add metaphor aliases to the CLI unless there is a later explicit product decision.
- Consider `hooks-global-install` and `hooks-global-uninstall` as future opt-in helpers.
  - Pros: a global checkout hook could detect a cloned nest, install local managed hooks automatically, and print or trigger first-restore guidance. This would help users working through GUI clients where they may not remember to run `git-nest hooks-install`.
  - Cons: global Git hooks affect every repository on a machine and can surprise users, slow unrelated checkouts, or conflict with existing global hook managers.
  - How to do it: keep it explicit, reversible, and visibly installed by git-nest. The global hook should only detect `.gitnest` and delegate to local `hooks-install` or guidance; it must not store hook-installed state in `.gitnest`.
  - How not to do it: do not silently edit global Git config, do not auto-run destructive `restore`, and do not make ordinary repositories depend on git-nest being installed.

# done

- Added platform-specific installation and invocation tips for Windows, Linux, and macOS to `README.md`.
- Added a command quick-reference table to the `README.md` command section.
- Replaced the old branch/upload/finalize workflow with normal Git branch/commit/push plus `git-nest snapshot`.
- Replaced public `sync` with `restore`.
- Added `repair` so `init` creates only and existing nests are repaired explicitly.
- Added `hooks-install` and `hooks-uninstall` as symmetric hook commands.
- Added local branch memory commands: `branch-mark`, `branch-unmark`, `branch-list`, and `branch-cleanup`.
- Added nested `init --sure` confirmation behavior.
