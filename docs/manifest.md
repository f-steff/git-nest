---
layout: default
title: Manifest Format
nav_order: 4
---

# git-nest Manifest Format

Manifest schema version: `1`

`git-nest` stores project state in `.gitnest`, an INI-style file tracked by the outer repository. Every manifest must contain `[project]` with `version=1`. git-nest validates the keys it owns, but accepts and preserves unknown sections and unknown keys where practical so other tools can add extension data. Duplicate git-nest-controlled sections, duplicate keys inside git-nest-controlled sections, malformed section headers, and malformed key lines are invalid.

Only the keys listed in this document are recognized and used by git-nest. Keys not listed here are treated as extension data: they are preserved verbatim across manifest rewrites, so external tooling can store its own metadata in `.gitnest`.

## Project Section

```ini
[project]
version=1
```

Recognized keys:

- `version=1` (required)
- `id=<name>` (optional) -- a project identifier, read by `snapshot --check`
  and used for branch-naming hints.
- `branch=<name>` (optional) -- a project-level branch note, shown by
  `status`.

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

## How It Is Validated

Every command that reads the manifest runs schema validation first
(`validate_manifest_schema`). Validation fails the command with a list of all
problems found, rather than silently proceeding on a broken manifest:

- `[project]` must exist with `version=1`; any other version is rejected.
- Duplicate `[project]` or `[subproject "..."]` sections, and duplicate keys
  inside a section, are rejected.
- Every subproject section must have a `repo` value.
- `clone` must be one of `full`, `partial`, or `shallow`.
- `tag` is only allowed together with `revision`.
- Subproject paths must be safe relative paths: no absolute paths, no parent
  escapes (`..`), no backslashes, and no Git-internal names (`.git`,
  `.gitnest`, `.gitnest.lock`, `.gitignore`, `.gitattributes`, and similar).

Keys listed in this document are validated with the rules above. Keys not
listed are not read or validated by git-nest; they are preserved as extension
data, as described in the preamble.
