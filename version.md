## 0.8.24 - 2026-08-11

### Repository cleanup
  * Relocated Jekyll site source (index.md, _config.yml, assets/,
    _includes/) from the repo root into `docs/site/`.
  * Merged `tools/serve-site.py` into `scripts/tools/` and deleted the
    `tools/` directory.
  * Added `scripts/README.md` describing the package and tool scripts.
  * Updated the quick-start intro in index.md to match the repository
    About text.
  * Synced AGENTS.md and development/github-pages.md with the new layout.

## 0.8.23 - 2026-08-11

### Tag CI dispatch for Pages badges
  * The release workflow now explicitly dispatches the three full CI
    suites on the newly created tag via `gh workflow run`, because
    `gh release create`'s tag push with `GITHUB_TOKEN` does not trigger
    additional workflow runs. This makes the Pages site version-pinned
    badges (`?branch=v{{ site.version }}`) go green automatically after
    every release.
  * The shfmt auto-installer now lowercases `uname -s` output so the
    download URL matches the actual GitHub release asset filename
    (the filename is lowercase but `uname -s` is capitalised).

## 0.8.22 - 2026-08-11

### CI infrastructure fixes
  * Fixed the shfmt auto-installer: `uname -s` returns "Linux" / "Darwin"
    (capitalised) but the GitHub release asset filenames are lowercase;
    the first download URL was wrong, which caused the fallback Windows
    binary to be downloaded on Linux runners (intermittently failing when
    the CDN happened to serve the capitalised URL correctly).
  * Version gate: added `--allow-equal` so tag CI dispatches (re-validating
    a past release for the version-pinned Pages badges) pass the gate
    when the version equals the last release tag. The release workflow
    still uses strict mode (no flag), so non-bump merges remain rejected.
  * CI workflows trigger on release tags (`v*`) so the Pages site badge
    URLs (`?branch=v{{ site.version }}`) reflect the release version's
    actual test status rather than the development-branch state.

## 0.8.21 - 2026-08-11

### Protocol and URL substitution for subproject remotes
  * Added a local per-developer protocol preference: `git-nest config set
    clone protocol ssh|https|http|manifest` stores the transport
    preference in `.gitnest-rc` (repo-wide, not committed).
  * `restore --prefer-ssh|--prefer-https|--prefer-http|--prefer-default`
    overrides the protocol for a single run and re-points each subproject's
    origin to the effective URL; `restore --dry-run` previews the change.
  * Per-subproject exact URL override: `git-nest config set <path>
    substitute-url <url>` for hosts whose SSH shape cannot be derived
    from the HTTPS URL (Azure DevOps, custom ports, Gerrit).
  * Transport is rewritten via environment-level git `insteadOf` per
    unique host -- zero persistent git-config writes, no call-site changes
    (git 2.31+ required for `GIT_CONFIG_COUNT` support).
  * `config list` now shows repo, clone-mode, substitute-url, protocol
    (from both the manifest and `.gitnest-rc`); the new rc-writing
    helpers support `config set`/`get`/`unset` for rc keys.
  * `verify` compares origin against the effective URL by default (host+path
    identity, protocol-tolerant); `verify --strict` checks the exact
    canonical manifest URL and rejects active rc overrides.
  * Documented the `url.<base>.insteadOf` pattern, `substitute-url`, and
    protocol preference in a new "Connecting To Your Remotes" section in
    the Manual.

## 0.8.20 - 2026-08-11

### Windows installation documentation
  * The QuickStart, the Manual, and the CI consumer guide now state
    explicitly that Windows requires Git for Windows (git-nest runs on
    Git Bash). Without it the installers complete but every `git-nest`
    command exits with "Git is not installed or not on PATH." (exit 3).
  * Added a direct PowerShell install option (`iex (iwr -useb ...)`)
    alongside the cmd.exe wrapper one-liner on the QuickStart, in the
    Manual, and in the CI consumer guide.

## 0.8.19 - 2026-08-10

### Installer and uninstaller fixes
  * Fixed the download installer's checksum verification: the tarball was
    downloaded as `git-nest.tar.gz` but verified against SHA256SUMS lines
    naming `git-nest-<version>.tar.gz`, so the documented `curl | sh`
    install always aborted. The tarball is now downloaded under the
    versioned name.
  * Fixed a dangerous uninstaller bug: all three uninstallers removed the
    entire `$prefix/share` directory, which could delete other tools'
    data when the prefix is a shared location such as `~/.local` (the
    default). They now remove only the git-nest-owned paths
    (`share/doc/git-nest`, `share/git-nest`, and the `git-nest*` man
    pages) and leave everything else intact.
  * Pinned-version examples in the README and the CI consumer guide use
    0.8.17 (the earliest published release) instead of the never-released
    0.8.16.
  * Quickstart on the documentation site: single deep link to the
    Manual's installation options; the second, redundant manual link was
    replaced with a brief tool introduction.
  * The Manual page on the site no longer contains the "Documentation:"
    link that pointed back at the site itself (the link remains in the
    README for the GitHub repository page).

## 0.8.18 - 2026-08-10

### Documentation site fixes
  * Fixed the GitHub Pages site: added the missing `baseurl: /git-nest` so
    CSS, assets, and page links resolve (the site rendered unstyled
    before), and enabled `.md` to `.html` link rewriting.
  * Sidebar: badge logo at the top with the site title below, a centered
    status section (latest release version + the three full CI badges),
    and a link back to the GitHub repository; the status section shares
    the header's width and horizontal center at every viewport.
  * Home page: quickstart links to the Manual's install section for more
    options; the full-width inline logo was removed (the logo now lives
    in the sidebar).
  * Replaced all mermaid diagram blocks with ASCII diagrams (5 in
    docs/examples.md, 1 in development/technical_docs.md) so the docs
    render without a mermaid runtime.
  * `_config.yml` gains a `version:` key shown as "Latest release" on the
    site; the version alignment check now keeps it in lockstep with
    `bin/git-nest-main.sh` and version.md.
  * Added `tools/serve-site.py`, a local preview server for the built
    site (documented in development/github-pages.md).

## 0.8.17 - 2026-08-10

### Distribution, installation, and project publishing
  * Added GitHub Pages site: Jekyll `just-the-docs` theme, inline SVG logo
    (the `\_oOO_//` mark, dark-mode aware, also the favicon), and automatic
    deployment on merge to main.
  * Added one-line installers: `git-nest-install.sh` (POSIX shells) and
    `git-nest-install.ps1` (PowerShell), supporting `VERSION=latest`
    (GitHub API) and `VERSION=x.y.z`, with SHA256SUMS verification.
  * Installers append the payload `bin/` to PATH by default;
    `--no-add-path` (sh/bat) or `GIT_NEST_ADD_PATH=0` (ps1) disables it
    for CI and scripted installs.
  * Renamed install/uninstall scripts to `git-nest-install.*` /
    `git-nest-uninstall.*`; uninstallers self-locate their installation,
    remove payload, staged docs/man/skill, and PATH configuration, and
    delete themselves.
  * Windows installers register git-nest in Apps & Features (Settings ->
    Apps) with a working uninstall entry; uninstallers remove it.
  * `git-nest help` prints the install path and the uninstaller name;
    README documents the installed layout tree and per-system
    install/uninstall instructions.
  * Added `docs/ci-consumer-guide.md` for DevOps engineers: per-CI-system
    install recipes (GitHub Actions, Azure Pipelines, GitLab CI, Gitea,
    Jenkins), private-subproject credentials, agent-image pattern.
  * Split docs: user-facing documentation stays in `docs/` (shipped in
    packages); maintainer documentation moved to `development/`.
  * Removed native package-manager stubs (Chocolatey, Homebrew, Scoop,
    Winget, APT, RPM, AUR) and the Amiga packaging target; the universal
    release tarball + install scripts are the sole distribution channel.
  * Renamed the implementation and awk modules to the `git-nest-*` naming
    convention (`git-nest-main.sh`, `git-nest-parse.awk`,
    `git-nest-tree-render.awk`).
  * CI automation: full test suites gate pull requests (Linux, macOS,
    Windows); merge to main runs the full Linux + fast macOS/Windows
    suites, deploys Pages, and auto-triggers the release workflow, which
    creates the `vX.Y.Z` tag and GitHub Release when the version gate
    passes.

## 0.8.16 - 2026-08-04

### Runner, cleanup, and documentation
  * Neutralized MSYS2 path-conversion in test runner and fixed mock/shim leaks.
  * Added cleanup command to test runner; it starts each run with workspace cleanup.
  * Added why-comments to all functions lacking purpose documentation.
  * Moved test suites under tests/ with integration-tests/ and unit-tests/ structure.
  * Dropped obsolete pending-workflow manifest keys and retired command handlers.
  * Added macOS/zsh test compatibility (BSD tar, sed, sleep, branch naming, symlinks).
  * Verified .bat and .ps1 launchers in the invocation smoke test.
  * Reorganized README with workspace model diagram, trimmed syntax, and further reading.
  * Reorganized todo.md into active, postponed, wont-do, and suggestions structure.
  * Added docs/howto.md with multi-step scenario recipes.
  * Documented two-tier test strategy in AGENTS.md testing guidelines.

## 0.8.15 - 2026-08-02

### PowerShell launcher and completions
  * Added git-nest.ps1 PowerShell launcher with walk-up Git Bash detection.
  * Added shell-neutral __complete engine with TSV protocol and 5 shell adapters (bash/zsh/fish/yash/powershell).
  * Fixed cursor_index off-by-one errors across all adapters.
  * Added __complete engine test for fish in the cross-shell runner.

## 0.8.14 - 2026-08-01

### POSIX compatibility and cross-shell testing
  * Fixed non-ASCII characters in unit tests for POSIX scanners.
  * Added POSIX compatibility testing documentation with shell syntax tables.
  * Added Docker-based cross-shell test runner covering bash, dash, ash, zsh, ksh, mksh, yash, and posh.
  * Fixed zsh cksum portability with fallback chain.
  * Added fish and pwsh to the Docker test matrix; all shells pass syntax, unit tests, and completions.

## 0.8.13 - 2026-07-31

### Unit test framework
  * Added unit test framework with mock Git shim (arg-diff mock, response files).
  * Expanded from 9 to 31 test files covering 86+ functions.
  * Added coverage ini (unit-tests.ini) and test 1990 for function coverage enforcement.
  * Fixed runner: mktemp for temp files, else-fi block structure.
  * Concise console runner output with per-test narrative and timing.

## 0.8.12 - 2026-07-30

### Tests and rename
  * Added comprehensive test documentation (tests/tests.md) with troubleshooting guide.
  * Deepened test coverage for gc, foreach --include-root, shallow clone, and freeze.
  * Renamed repair command to tidy throughout the codebase and documentation.
  * Removed deprecated repair command handler completely.

## 0.8.11 - 2026-07-29

### GC, foreach, and shallow clone
  * Added git-nest gc: prune unreferenced objects across all subproject repositories.
  * Added foreach --include-root-first/--include-root-last for nest-root-inclusive iteration.
  * Added shallow clone mode (clone-mode=partial) for bandwidth-efficient restores.

## 0.8.10 - 2026-07-28

### Nest codes and foreach filters
  * Added unmanaged (U) and composite (C) nest root codes in tree and survey output.
  * Added foreach --only-nested/--no-nested filters for targeted subproject iteration.
  * Linked version.md from README for release traceability.
  * Improved error messages with actionable context.

## 0.8.9 - 2026-07-27

### Documentation and survey improvements
  * Removed superseded survey_pull_feature design documents from the repository.
  * Added survey detection of un-initialized submodules with actionable next-step suggestions.
  * Added CI documentation (docs/ci_and_dockerized_testing.md).
  * Fixed non-ASCII em-dash in docs/examples.md.

## 0.8.8 - 2026-07-25

### Bug fixes and hardening
  * Fixed variable-collision bugs in path/repo handling across commands, manifest, hooks, and conversion.
  * Implemented init/absorb-all nested-nest-overlap refusal: init inside a managed subproject requires --sure.
  * Added docs/examples.md with comprehensive usage recipes.
  * Fixed No URI descriptions and non-ASCII characters in examples.

## 0.8.7 - 2026-07-23

### Enriched tree output
  * Added root line showing the project name/nest root in tree output.
  * Added repository URLs, type labels (managed/unmanaged/composite), and checkout state markers.
  * Added --plain mode for minimal output without state annotation.

## 0.8.6 - 2026-07-22

### Tree command
  * Added git-nest tree: visual directory-tree rendering of the nest with subproject type labels, URLs, and repository state.
  * Added --porcelain and --json modes for script-friendly output.
  * Centered output on a single +-- connector with trailing / for directories.

## 0.8.5 - 2026-07-20

### absorb-all, pull, and documentation
  * Added absorb-all: recursively convert all nested repositories and submodules into managed subprojects in one pass.
  * Added JSON output to pull and hardened pull edge-case handling.
  * Documented survey, absorb-all, absorb --subrepo/--subtree, and pull.

## 0.8.4 - 2026-07-19

### Survey, boundaries, and paths
  * Added survey command replacing discover: read-only scan for nest-managed subprojects, uninitialized submodules, and detached former subprojects.
  * Enforced project-boundary safety: write-side commands refuse parent-to-nested-project path crossings.
  * Hardened paths-with-spaces handling across absorb --subrepo/--subtree, pull, and boundary enforcement.

# Version History

## 0.8.3 - 2026-07-18

### Quality and maintainability

- Split monolithic `bin/git_nest.sh` (7414 lines) into 6 focused files under `bin/lib/` and `bin/git_nest.sh` (small entrypoint).
- Added manifest cache: single awk pass populates shell variables, replacing N-per-key subprocess reads with O(1).
- Added ShellCheck configuration (`bin/.shellcheckrc`) with documented suppressions; all warnings fixed.
- Added `tests/check.sh` -- unified quality script running `sh -n`, ShellCheck, `shfmt`, `checkbashisms` with auto-install of missing tools to `~/bin/`.
- Added `test_0000_static_code_analysis.sh` -- runs quality checks as part of the test suite.
- Added command trace log (`$TEST_ROOT/.git-nest-commands.log`) for full-suite auditability.
- Removed ~350 lines of dead code (old `start`/`upload`/`finalize` workflow).
- Fixed `sleep_ms` lookup table -> POSIX awk-based fractional sleep.
- Fixed CRLF line endings in all shell files.
- Added POSIX formatting via `shfmt -w -ln posix` across all shell files.
- Added `-v` short flag for version.
- Added `--help`/`-h` on subcommands (parses before `--` separator).
- Added `--online` flag on `doctor` as explicit documentation pair for `--offline`.
- Added `docs/exit-codes.md`.
- Added `debug` and `release` to `DISCOVER_DEFAULT_EXCLUDES`.
- Added Go port analysis to `todo.md`.
- Renamed `docs/implementation-summary.md` -> `docs/command-behavior-contract.md`.
- Fixed `.bashrc` guard for optional `git-subrepo` sourcing.

## 0.8.2 - 2026-07-16

### Nest membership commands

- Reworked outer-repository conversion into a direction-clear set. `absorb` now brings something already on disk into the nest, auto-detecting the source: outer-repository tracked files (the former `extract`, requiring a remote URL and supporting `--branch`, `--clone-mode`, `--preserve-history`, `--push`, `--message`, and `--force`), a standalone nested repository (recording its own remote and current commit), or a Git submodule (converted into a standalone managed subproject).
- Renamed the old fold-out behavior to `inline` (dissolve a subproject into ordinary outer-repository files) and added `detach` (remove a subproject from the nest but keep its checkout as a standalone, still-ignored repository, formerly `remove --keep-files`).
- `remove`/`rm` now always deletes the checkout; `extract` and `remove --keep-files` are rejected with guidance. `absorb` refuses a path that is already a subproject and refuses deeper nested repositories/submodules. All of `absorb`, `inline`, `detach`, and `remove` support `--dry-run` and `--json`/`--json-pretty`.
- Added `discover`: a bounded, read-only scan for nested repositories and submodules not managed by `.gitnest`, with `--max-depth` and repeatable `--exclude`, symlink-safe traversal, kind classification (including `detached` former subprojects), and suggested next steps.
- Added `list`: a stable-order inventory of managed subprojects with URL, target branch, revision, tag, checkout state, and reproducibility, in human, `--porcelain`, and `--json` forms.

### Ignore hygiene and recovery backups

- Managed nest-owned `.gitignore` entries in a self-healing `# BEGIN git-nest ignores` block: entries a user moves outside the block are pulled back in and deduped, `repair` prunes stale entries whose path is gone, and `doctor` warns when stale entries exist.
- Reworked conversion backups into transient, self-documenting `.gitnest-recovery-<op>-<name>-<timestamp>/` directories with a `RECOVERY.txt`, ignored on demand through the repo-local `.git/info/exclude` (never the committed `.gitignore`) and removed on success. `doctor` reports leftover recovery backups from an interrupted conversion.

### Hardening and diagnostics

- Rejected unsafe subproject paths in the manifest content itself (absolute, `..` escape, backslash, Git-internal names) during schema validation, so no command clones, checks out, or removes outside the nest root.
- Refused case-only-different subproject paths in `add`, `move`, and `absorb` to prevent collisions on case-insensitive filesystems.
- Added `--redact` to `list` and `doctor` to strip credentials from URLs and the home directory from paths in their output.

### Bug fixes

- `cmd_snapshot` returned the trailing notice's status instead of the snapshot result, so the root pre-push hook's reproducibility warning never fired; it now returns the real result.
- `verify --json` always returned empty `errors`/`warnings` arrays because `verify_current` clobbered the caller's temp-file variables; it now writes to caller-provided files with separated errors and warnings.
- Submodule `absorb` relocates the submodule git directory into the checkout and clears the stale `core.worktree`, leaving a usable standalone repository.

### Test framework

- Gave every test a globally unique four-digit ID (filename prefix `test_<NNNN>_<category>_<behavior>.sh`) in category blocks stepping by 10, and a `# Test:` description header per file.
- Added runner commands `list` (ID + description), `only <ids>`, `except <ids>`, and `help`, plus a `--stop-on-fail` option; an unknown command, option, or test ID prints help and stops.
- The console shows a curated per-test narrative (each git-nest command with its output) by default; `--verbose` streams the full raw output with a shell trace, and a failing test dumps its full raw output. Summary columns size to the longest test name.
- Added a full-run log (`run-all-tests.log` by default, `--no-log`/`--log FILE`) and renamed the Markdown summary to `run-all-tests-results.md`.
- Added and deepened tests for absorb sources, detach, discover, list, verify health, and hooks (install, uninstall, and real trigger-through-Git), and made the invocation smoke check a real test.
- Completed a coverage-deepening pass across the command surface: added restore materialization/re-clone/partial-failure coverage and extended status (JSON, composite state, flag conflicts), outdated/diff (JSON), log (--until), freeze (clean no-force), clone (--branch/--depth/--single-branch), and doctor (stale-ignore and recovery-backup checks).

### Skills and documentation

- Made `skills/git-nest/SKILL.md` the single source of truth for the usage skill, with a discoverable pointer at `.agents/skills/git-nest/SKILL.md`, and documented the two skill trees and development-agent bootstrap in `AGENTS.md`.
- Updated `README.md`, `docs/command-behavior-contract.md` (formerly `docs/implementation-summary.md`), `docs/technical_docs.md`, `docs/maintainer.md`, and the usage skill throughout for the new commands and workflows.

## 0.8.1 - 2026-07-08

- Changed name from `git-lego` to `git-nest` to better reflect the tool's role as a shared home for independent Git repositories and to avoid using the name of a commercial product.
- Renamed the command surface from `git-lego` / `git lego` to `git-nest` / `git nest`.
- Renamed project-owned state from `.gitlego` and `.gitlego-rc` to `.gitnest` and `.gitnest-rc`.
- Renamed implementation, schema, documentation, tests, and the portable AI skill to use the `git-nest` name.
- Renamed the command output JSON Schema from `schemas/git-lego-output-v1.schema.json` to `schemas/git-nest-output-v1.schema.json` (the `version` field and content contract are unchanged and backward-compatible).
- Preserved the historical `git-stack` name and stack/module terminology in pre-0.5.0 version history entries.
- Added the `\\_oOO_//` nest-and-eggs logo after the name and version in version command output, keeping the first two fields script-friendly.
- Added platform-specific installation and invocation guidance for Windows, Linux, and macOS.
- Added a README command quick reference with a brief purpose statement for each command.
- Added grouped help output and `git-nest help <command>` pages with command-specific explanations, examples, and symmetric command guidance.
- Clarified `git-nest clone <nest-repo-url>` as a `git clone` plus `git-nest restore` convenience, distinct from subproject `clone-mode`.
- Clarified `config` as an allowlisted manifest setting command; currently only `clone-mode=full|partial` is public, and unknown keys are rejected.
- Added `doctor` informational checks for optional export helpers: system `tar` for `tar.gz` output and `python` / `python3` for `zip` output.
- Updated generated test result tables so test names render as inline code.
- Added `todo.md` to track pending design work, documentation suggestions, and completed release tasks.
- Cleaned up `todo.md` into active todo, suggestions, and done sections, including future submodule/subtree/git-subrepo conversion design notes.
- Reworked the workflow around normal Git branch, commit, and push operations plus `git-nest snapshot` for recording reproducible subproject revisions.
- Replaced the public `sync` command with `restore`, so restoring files from the manifest is named separately from recording manifest state.
- Removed the public branch/upload/finalize/pending workflow commands; old names now fail with guidance toward the new workflow.
- Added `repair` so `init` creates only, while managed support files are refreshed explicitly.
- Added local branch-memory commands: `branch-mark`, `branch-unmark`, `branch-list`, and `branch-cleanup`.
- Added `move` as the long-form alias for `mv`, matching `remove` / `rm` symmetry.
- Renamed hook management to `hooks-install` and `hooks-uninstall`, and split root and subproject hook behavior around restore/snapshot reproducibility.
- Added nested `init --sure` protection so accidental nests inside managed subprojects are rejected by default.
- Updated README, implementation summary, maintainer guidance, AGENTS.md, and the portable AI skill for the restore/snapshot model.

## 0.7.1 - 2026-07-04

Polish and hardening release. No breaking changes.

- Added: `git-lego doctor` command for environmental preflight checks.
- Added: `--dry-run` support on `sync`, `snapshot`, `upload`, and `finalize`.
- Added: README "Limitations And Non-Goals" section.
- Added: README "Recovery Cookbook" section.
- Added: README per-command side-effect matrix.
- Hardened: backslash path refusal across write-side commands that accept subproject paths.
- Hardened: reserved-name and `.git` segment refusal for subproject paths.
- Hardened: `git-lego init` now repairs the managed `.gitattributes` block for git-lego line endings.
- Documentation: README, skill guidance, technical notes, implementation summary, AGENTS.md, and maintainer guide updated for 0.7.1.
- Schema: `git-lego-output-v1.schema.json` extended to cover `doctor` output and dry-run markers, backward-compatible.

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

- Added mandatory `.gitlego` manifest schema `version=1` and `manifest.md`.
- Added command-scoped `.gitlego.lock` protection for manifest writers.
- Hardened auto-finalize ticket matching, base revision resolution, tag drift checks, and `.gitignore` deduplication.
- Added README security considerations.

## 0.5.0 - 2026-07-03

- Changed name from `git-stack` to `git-lego` to avoid confusion with another `git-stack` tool with radically different features.
- Renamed manifest and terminology from stack/module to project/subproject.
- Renamed `refresh` to `snapshot`, `available` to `outdated`, `check` to `no-pending`, and `foreach-modified` to `foreach-pending`.
- Switched the license from AGPL-3.0-or-later to MIT.
- Added the `.gitlego text eol=lf` `.gitattributes` guard.

Historical note: releases before 0.5.0 were published as `git-stack`. Version
0.5.0 is the rename boundary where the tool became `git-lego` to avoid
confusion with another `git-stack` tool with radically different features.
Pre-0.5.0 entries therefore use the old command name, stack/module terminology,
and legacy command names as they existed at the time.

## 0.4.2 - 2026-06-29

- Added stale module path reconciliation during `git-stack sync`.
- Automatically moves clean, pushed modules when manifest paths change.
- Automatically removes clean, pushed modules that are no longer in the manifest.
- Added `git-stack sync --prune` for explicit stale local-state cleanup after warnings.
- Documented stale cleanup notices, warnings, and ambiguity handling.

## 0.4.1 - 2026-06-26

- Added porcelain output for `git-stack status` and `git-stack available`.
- Expanded `git-stack --help` with brief command and option descriptions.
- Made local rc configuration optional by default and added `git-stack init --rc`.
- Renamed the local manifest update command from `record` to `refresh`.
- Propagated managed hooks to modules added or cloned after hooks are installed.
- Moved the default integration test root outside the repository.
- Documented script-friendly dirty and available checks.

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
- Established the manifest format and module layout.
