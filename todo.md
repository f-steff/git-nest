# todo

TBD.

The former distribution-method and GitHub-CI items are done: distribution
is the universal release tarball plus the install scripts (see
`development/distribution-overview.md`), and CI is PR-gated with
automatic release on merge (see `development/release-process.md`).

# won't do

Decided against. Do not build these; the documented recipes and the
plain refusal are the supported behavior.

- **Multi-nest operations** -- make changes to multiple git nests in one
  command, such as moving a subproject from one nest into a nested nest.
  This includes the automated `init --adopt` (Option C) that would
  reconcile a nested-nest overlap by rewriting two manifests in one
  operation. It would need multi-conflict handling in one pass, atomic
  updates to two `.gitignore` managed blocks, and a cross-manifest
  recovery/rollback story -- disproportionate complexity for a rare
  scenario. The manual `detach`/`init`/`absorb` recipe is the supported
  path.

- **Promote the cross-repository feature-branch workflow to first-class
  commands** -- the single-pass `foreach-modified` recipes already cover
  starting, committing, and pushing a feature across the dirty
  subprojects, followed by `git-nest snapshot`. First-class
  `branch`/`commit`/`push` commands would only add value for
  participant tracking and the post-PR-merge return step, which the
  recipes cannot express cleanly. Implementing them would make git-nest
  a branch/merge authority again -- the very thing `start`, `upload`,
  and `finalize` were removed for. Do not resurrect those names or
  semantics, and do not store workflow state in `.gitnest`.

# postponed

Items below have had deeper analysis performed (pros, cons, and a
decision), but the decision was not to build them now. Revisit only if
the stated trigger condition actually occurs in practice.

- **Go port** -- consider a port if the shell implementation becomes too
  large to maintain: routinely exceeds 10k lines, or contributors
  report that shell-based development is a significant barrier.
  - Pros: native cross-compilation for Windows/Linux/macOS without Git
    Bash; typed data structures and proper JSON; goroutines for
    concurrent subproject operations (a huge win for `restore`/`foreach`
    with 100+ subprojects); static binary distribution; eliminates the
    Windows process-startup overhead that makes the shell test suite
    ~19x slower than on Linux.
  - Cons: adds a build step and Go toolchain requirement; loses the
    edit-and-run iteration loop; `go-git` credential/transport handling
    may differ from system `git`; the tool's simplicity is a feature.
  - For the 0.x lifetime, keep shell and invest in module splits
    (`lib/`) and ShellCheck. The `--jobs` and awk-removal items below
    may accelerate this decision.
  - Distribution impact if ported: per-target binaries replace the
    universal shell tarball (GOOS/GOARCH matrix: linux/amd64+arm64,
    darwin/amd64+arm64, windows/amd64, optional windows/arm64). Code
    signing becomes mandatory on two platforms: Authenticode for
    Windows (Azure Trusted Signing or OV/EV certificate, SmartScreen)
    and Apple Developer ID + notarization/stapling for macOS
    ($99/year). Linux needs none (distro repos carry trust). Every
    package format (brew, Scoop, Winget, Chocolatey, APT, RPM, AUR,
    Nix, Snap) gains per-arch artifacts and platform signing; see the
    distribution investigation notes for the per-target table.
  - CI-agent impact if ported: a single static binary is trivially
    installed on runners (no interpreter, no MSYS layer, and the
    Windows startup gap largely disappears); Windows agents still
    benefit from Authenticode signing for corporate policies, macOS
    agents want a notarized artifact if it doubles as the end-user
    binary, and digest-pinned Docker images stay the Linux pattern.

- **Architecture diagram** (`docs/architecture.md`) -- an ASCII or
  Mermaid diagram showing module relationships, data flow for key
  commands (restore, snapshot, absorb), and the manifest cache
  lifecycle. Nice to have for first-time contributors but no behavioral
  impact. Best done after the codebase stabilizes further.

- **Parallel test runner** (`run-all-tests.sh --jobs <N>`) -- run tests
  in parallel batches with workspace isolation. The current sequential
  runner works correctly and the full suite is acceptable per the
  maintainer docs. High effort for moderate gain.

# suggestions (ponder)

Items in priority order.

1. **`git-nest tui` -- minimal pure-POSIX-shell terminal UI**
   Interactive front-end over the existing inspection commands. Every
   action spawns a fresh `git-nest` instance and captures its output.
   Implemented in `bin/lib/git-nest-tui.sh` (~400-500 lines), split as a
   testable "functional core + imperative shell":
   - **Pure functions** (unit-testable, no TTY/git): `tui_key_normalize`
     (byte sequences -> tokens), `tui_box`/`tui_clip`/`tui_wrap` (ASCII
     rendering), `tui_trim_help` (extract description + bullets from
     `git-nest help <cmd>`), `tui_layout` (rows/cols -> pane rects),
     `tui_menu_step` (two-tier menu state machine),
     `tui_input_step` (input-strip buffer machine).
   - **Imperative shell** (thin, integration-tested): `tui_read_key`
     (`stty -echo -icanon min 0 time 1` + `dd bs=1`, `stty -g` save +
     `trap ... EXIT INT TERM HUP` restore), `cmd_tui` (gate), `tui_run`
     (render loop, `Ctrl-L` re-measure via `stty size`).
   - **Panes**: 1-line header (title + nest root + count + hotkey
     legend); menu pane on the left (level 1 = actions: Status, Tree,
     List, Survey, Verify, Outdated, Diff, Doctor, Snapshot, Pull,
     Restore, GC, Freeze, Help; level 2 = subproject picker from
     `git-nest list --porcelain` for path-taking actions; ESC pops
     back); read-only description pane on the right (actions: cached
     `git-nest help <cmd>` trimmed; subprojects: state lines); full-width
     scrollable log pane at the bottom (`>`-prefixed commands + output,
     seeded with `> git-nest version`, capped buffer).
   - **Focus**: Tab forward, Shift-Tab (`ESC [ Z`) backward, cycling
     menu -> description -> log. Per-pane arrows (menu moves highlight,
     log/description scroll).
   - **Keys**: `↑/↓/←/→` = `ESC [ A/B/C/D`; Enter = `\r`; Tab = `\t`;
     Shift-Tab = `ESC [ Z`; ESC = `\x1b`; Ctrl-H = `\x08`; Ctrl-L =
     `\x0c`; Ctrl-C = `\x03`; `q` quits. Lone ESC vs arrow disambiguated
     by the `min 0 time 1` timeout. Help overlay on Ctrl-H.
   - **Actions**: class 1 (zero-arg whole-nest commands), class 2
     (path-targeted: snapshot/update/detach/remove/inline, with an
     inline `[y/N]` confirm for destructive ones), class 3 (single-line
     input strip for add/move/clone/update/export/branch-mark/config --
     one required free-text field per command, not a command palette).
   - **Gate**: require a real terminal (`[ -t 0 ] && [ -t 1 ]` + a
     `stty` probe); on failure print a one-line message and exit cleanly
     (terminal never left raw). On Windows the `.bat`/`.ps1` launchers
     both attach bash to the console (not mintty), so `tui` only works
     from a Git Bash window; each launcher sets
     `GIT_NEST_WIN_LAUNCHER` (cmd / powershell) so the gate message can
     name the caller. The `.bat` marker goes in the cmd.exe half only
     (before the `BATCH` heredoc terminator); the sh half and
     `bin/git-nest` set nothing.
   - **Rendering**: ASCII-only, full printable set (`+ - | = # * : / \ _
     . ~`), no box-drawing Unicode; ANSI escapes emitted via
     `printf '\033'` so the source stays ASCII (check_ascii enforced).
   - **Tests**: pure-function unit tests (key parser, box, wrap, trim,
     layout, menu/input state machines) with `# Coverage:` headers; a
     new integration test `test_0117_command_tui.sh` covering gate
     refusal (non-tty stdin exits nonzero with a clean message),
     `tui --help`/`help tui`/completion listing, static launcher-marker
     checks, and a pty smoke test guarded to non-Windows (`script
     -qec`/`expect`; skipped on Windows).
   - Reserve `gui` for a future windowed front-end (mirroring
     `git gui`).
   - Status: **in progress** on branch `interactive_tui`.

2. **`--jobs <N>` parallelism** -- for `restore`, `snapshot`, `pull`,
   `foreach`. Shell background processes with a job counter and `wait`.
   Gate behind `--jobs` so existing behavior is unchanged. Include a
   progress indicator for human output. This is the strongest argument
   for the Go port, since shell background-process management is
   inherently fragile.

3. **Performance/scale tests** -- create a nest with 20, 50, 100
   subprojects (script-generated remotes) and verify that `status`,
   `list`, `restore --dry-run`, `snapshot --dry-run` complete within
   reasonable time. Mark as `[slow]` and gate behind `--include-slow`.

4. **`absorb-all --only-submodules` / `--only-repos` filter flags** --
   narrow `absorb-all` to only submodule registrations (`.gitmodules`
   entries) or only standalone nested repos. Useful for migration
   scenarios where you want to convert only one kind at a time.

5. **Remove awk dependency** -- replace `git-nest-parse.awk` with a
   pure-shell manifest parser (slower but awk-free). Replace
   `git-nest-tree-render.awk` with shell `printf`/`sed` loops. Replace 30+ awk
   one-liners with `sed`/`cut`/`grep` equivalents. Eliminates
   GNU-vs-BSD-vs-BusyBox awk variance. Low priority -- the current awk
   usage is POSIX and a BusyBox compatibility test exists. Revisit if
   awk causes portability issues in practice.
