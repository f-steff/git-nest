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
  - Include at least path, URL, branch, revision, current checkout state, and whether the entry is finalized.
  - Keep `status` focused on workspace health. Do not make scripts depend on decorative or human-oriented status output.
- Design a conservative current-branch update workflow:
  - Consider `git-nest pull`, `git-nest update-current`, or a documented `foreach-clean -- git pull --ff-only` recipe.
  - The command should update checked-out modules on their current branches without first rewriting module state from `.gitnest`.
  - Refuse dirty worktrees, staged changes, unresolved conflicts, and ambiguous detached-HEAD states unless an explicit option says otherwise.
  - Prefer fast-forward-only behavior by default and clearly report modules that require manual merge/rebase work.
  - Do not make this a replacement for `sync`, `snapshot`, `upload`, or `finalize`. It is a working-tree convenience, not a manifest authority.
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
  - Do not merge subtree or git-subrepo behavior into `adopt-submodule`, `eject-submodule`, `sync`, or `finalize`.
  - Do not hide history-loss or history-boundary semantics behind a friendly command name. The dry-run and confirmation text must say exactly what history is and is not being carried across.

# suggestions

- Use nest-related vocabulary in documentation examples to make command explanations more memorable, while keeping the actual command names literal and script-friendly.
  - Example: describe `sync` as bringing the nest back into shape, or as hatching missing checkouts, without adding `hatch` as a code alias.
  - Do not add metaphor aliases to the CLI unless there is a later explicit product decision.

# done

- Added platform-specific installation and invocation tips for Windows, Linux, and macOS to `README.md`.
- Added a command quick-reference table to the `README.md` command section.
