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

1. **`--jobs <N>` parallelism** -- for `restore`, `snapshot`, `pull`,
   `foreach`. Shell background processes with a job counter and `wait`.
   Gate behind `--jobs` so existing behavior is unchanged. Include a
   progress indicator for human output. This is the strongest argument
   for the Go port, since shell background-process management is
   inherently fragile.

2. **Performance/scale tests** -- create a nest with 20, 50, 100
   subprojects (script-generated remotes) and verify that `status`,
   `list`, `restore --dry-run`, `snapshot --dry-run` complete within
   reasonable time. Mark as `[slow]` and gate behind `--include-slow`.

3. **`absorb-all --only-submodules` / `--only-repos` filter flags** --
   narrow `absorb-all` to only submodule registrations (`.gitmodules`
   entries) or only standalone nested repos. Useful for migration
   scenarios where you want to convert only one kind at a time.

4. **Remove awk dependency** -- replace `git-nest-parse.awk` with a
   pure-shell manifest parser (slower but awk-free). Replace
   `git-nest-tree-render.awk` with shell `printf`/`sed` loops. Replace 30+ awk
   one-liners with `sed`/`cut`/`grep` equivalents. Eliminates
   GNU-vs-BSD-vs-BusyBox awk variance. Low priority -- the current awk
   usage is POSIX and a BusyBox compatibility test exists. Revisit if
   awk causes portability issues in practice.
