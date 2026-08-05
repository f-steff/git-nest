#!/bin/sh
# Test: every --json command emits output that validates against the shared schema

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_json_schema

test_step "Validate JSON output against the shared schema" "Every --json command must emit the same versioned envelope (version, command, recursive, ok, subprojects, errors, warnings) with the seven-column row shape, as documented in schemas/README.md. This test builds a small nest and validates output from several inspection commands against schemas/git-nest-output-v1.schema.json."

root=$(test_workspace contract_json_schema)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"
json_dir="$root/json"

mkdir -p "$root/remotes" "$root/seed" "$json_dir"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

# Collect JSON output from every command that supports --json. Output files go
# outside the outer repo so they do not dirty the workspace under test.
run_capture "status --json" "$json_dir/status.json" "$json_dir/status.err" -- "$GIT_NEST" status --json
run_capture "verify --json" "$json_dir/verify.json" "$json_dir/verify.err" -- "$GIT_NEST" verify --json
run_capture "outdated --json" "$json_dir/outdated.json" "$json_dir/outdated.err" -- "$GIT_NEST" outdated --json
run_capture "list --json" "$json_dir/list.json" "$json_dir/list.err" -- "$GIT_NEST" list --json
run_capture "tree --json" "$json_dir/tree.json" "$json_dir/tree.err" -- "$GIT_NEST" tree --json
run_capture "survey --json" "$json_dir/survey.json" "$json_dir/survey.err" -- "$GIT_NEST" survey --json
run_capture "doctor --json --offline" "$json_dir/doctor.json" "$json_dir/doctor.err" -- "$GIT_NEST" doctor --json --offline
run_capture "foreach-modified --json" "$json_dir/foreach.json" "$json_dir/foreach.err" -- "$GIT_NEST" foreach-modified --json

# Each capture must be parseable JSON with the envelope's required keys.
for f in status verify outdated list tree survey doctor foreach; do
    assert_file_contains "$json_dir/$f.json" '"version":1'
    assert_file_contains "$json_dir/$f.json" '"subprojects"'
    assert_file_contains "$json_dir/$f.json" '"errors"'
    assert_file_contains "$json_dir/$f.json" '"warnings"'
done

# Validate every captured file against the shared schema with Python. This
# needs the third-party jsonschema package; when it is absent, fall back to
# Python's stdlib json module to confirm the envelope keys and row shape so the
# test still does meaningful work on minimal systems.
python - "$REPO_ROOT/schemas/git-nest-output-v1.schema.json" \
    "$json_dir/status.json" "$json_dir/verify.json" "$json_dir/outdated.json" \
    "$json_dir/list.json" "$json_dir/tree.json" "$json_dir/survey.json" \
    "$json_dir/doctor.json" "$json_dir/foreach.json" <<'PY'
import json
import sys
import importlib.util

schema_file = sys.argv[1]
data_files = sys.argv[2:]

with open(schema_file, encoding="utf-8") as f:
    schema = json.load(f)

parsed = []
for path in data_files:
    with open(path, encoding="utf-8") as f:
        parsed.append((path, json.load(f)))

if importlib.util.find_spec("jsonschema"):
    import jsonschema
    for path, data in parsed:
        try:
            jsonschema.validate(data, schema)
        except jsonschema.ValidationError as exc:
            print(f"SCHEMA VIOLATION in {path}: {exc.message}", file=sys.stderr)
            sys.exit(1)
else:
    # Minimal stdlib fallback: envelope keys + row shape.
    for path, data in parsed:
        for key in ("version", "command", "recursive", "ok", "subprojects", "errors", "warnings"):
            if key not in data:
                print(f"SCHEMA ENVELOPE MISSING in {path}: {key}", file=sys.stderr)
                sys.exit(1)
        for row in data["subprojects"]:
            for key in ("code", "path", "state", "target", "current", "expected", "detail"):
                if key not in row:
                    print(f"SCHEMA ROW MISSING in {path}: {key}", file=sys.stderr)
                    sys.exit(1)
    print("jsonschema not installed; used stdlib envelope/row check")

print("ALL COMMANDS VALIDATED")
PY

describe_result "Every --json command emitted output that validates against the shared schema."
