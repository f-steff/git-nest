# JSON Output Schema

This directory contains the JSON Schema that describes git-nest's
machine-readable output. This document explains what the schema is for and how
to consume it.

## What It Is

`git-nest-output-v1.schema.json` is a published contract for the JSON that
git-nest commands emit when invoked with `--json` or `--json-pretty`. It is
aimed at **consumers**: scripts, CI pipelines, editor integrations, or other
tools that parse git-nest output and need a stable, versioned shape to rely on.

It is not used by git-nest itself at runtime. git-nest builds its JSON output
directly from shell code; the schema is a description of that output, verified
by the project's test suite, so consumers can trust it.

## Which Commands

The `command` field is restricted by the schema to:

`status`, `verify`, `outdated`, `diff`, `foreach-modified`,
`foreach-clean`, `doctor`, `absorb`, `absorb-all`, `inline`, `detach`,
`remove`, `list`, `tree`, `survey`, `pull`

Every one of these emits the same envelope and the same row shape, so a
consumer only needs one validator for all of them.

## The Envelope

Every `--json` result is a single JSON object with these keys:

| Key | Type | Meaning |
|-----|------|---------|
| `version` | integer (always `1`) | Schema version this output conforms to. |
| `command` | string | The command that produced the output. |
| `dry_run` | boolean (optional) | Present when `--dry-run` was used. |
| `recursive` | boolean | Whether `--recursive` applied. |
| `ok` | boolean | Overall success of the command. |
| `subprojects` | array of rows | One entry per subproject (or action). |
| `errors` | array of strings | Human-readable error messages. |
| `warnings` | array of strings | Human-readable warnings. |
| `checks` | array of checks | Doctor-only health check results. |

### Row shape

Each row in `subprojects` has the same seven fields:

`code`, `path`, `state`, `target`, `current`, `expected`, `detail`

The `code` is a single character (for example `M` for managed, `R` for
unmanaged repository). The other fields are plain strings; empty strings are
used when a value does not apply.

### Doctor checks

`doctor --json` adds a `checks` array. Each check has:

`code` (one of `I`, `W`, `E`), `name`, `status` (`info`, `warn`, `error`),
and `detail`.

## Consuming The Schema

Fetch the schema from its canonical URL:

```
https://github.com/f-steff/git-nest/schemas/git-nest-output-v1.schema.json
```

Validate output with any JSON Schema implementation. For example, with Python:

```sh
python -m pip install jsonschema
```

```python
import json
import jsonschema

with open("git-nest-output-v1.schema.json", encoding="utf-8") as f:
    schema = json.load(f)
with open("output.json", encoding="utf-8") as f:
    data = json.load(f)

jsonschema.validate(data, schema)
```

The schema uses JSON Schema draft 2020-12 and sets `additionalProperties:
false`, so any key git-nest emits that is not listed here is a schema violation
and should be reported to the maintainers.

## Compatibility

The `version` field is the compatibility contract. Output carrying
`"version":1` conforms to this schema. If git-nest ever changes the output
shape in a breaking way, a new `git-nest-output-vN.schema.json` will be
introduced and the `version` field will be bumped; the old schema file stays
in place for consumers that have not migrated.

## Relationship To --porcelain

`--porcelain` produces the same row data (`code`, `path`, `state`, ...) as
stable, tab-separated text. Choose `--porcelain` for simple shell parsing and
`--json` (validated against this schema) when you need structured data or
share output across tools.

## Historical Note

The schema was first published as `git-lego-output-v1.schema.json` (version
0.5.2) and renamed to `git-nest-output-v1.schema.json` when the project was
renamed from git-lego to git-nest in 0.8.1. The content contract is
backward-compatible across the rename.
