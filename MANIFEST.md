# git-nest Manifest Format

Manifest schema version: `1`

`git-nest` stores project state in `.gitnest`, an INI-style file tracked by the outer repository. Every manifest must contain `[project]` with `version=1`. git-nest validates the keys it owns, but accepts and preserves unknown sections and unknown keys where practical so other tools can add extension data. Duplicate git-nest-controlled sections, duplicate keys inside git-nest-controlled sections, malformed section headers, and malformed key lines are invalid.

## Project Section

```ini
[project]
version=1
```

Required key:

- `version=1`

## Subproject Sections

Each subproject is stored in one section whose name is the project-root-relative path:

```ini
[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
revision=<sha>
```

Common keys:

- `repo=<url-or-path>` is required.
- `clone=<full|partial|shallow>` is optional; `shallow` creates a shallow clone (depth defaults to 1).
- `target_branch=<branch>` records the upstream branch used for comparisons.

Recorded state:

- `revision=<sha>` pins a commit.
- `tag=<tag>` may be present only with `revision=<sha>`.
- `depth=<n>` sets the shallow clone depth when `clone=shallow`.

Obsolete keys from earlier unreleased workflows are invalid:

- `pending_branch=<branch>`
- `base_revision=<sha>`
- `pushed_commit=<sha>`
- `finalized_from_branch=<branch>`
