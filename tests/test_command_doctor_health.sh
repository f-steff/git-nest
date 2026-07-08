#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_doctor_health

test_step "Exercise command doctor health" "This test verifies the documented command doctor health behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_doctor_health)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

"$GIT_NEST" doctor --offline >doctor.out
assert_file_contains doctor.out "I	git-version"
assert_file_contains doctor.out "I	remotes	remote reachability skipped by --offline"

"$GIT_NEST" doctor --json --offline >doctor.json
python -m json.tool doctor.json >/dev/null 2>&1 || python3 -m json.tool doctor.json >/dev/null
assert_file_contains doctor.json '"command":"doctor"'
assert_file_contains doctor.json '"checks"'
assert_file_contains doctor.json '"status":"info"'
if python - <<PY >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec("jsonschema") else 1)
PY
then
    python - "$REPO_ROOT/schemas/git-nest-output-v1.schema.json" doctor.json <<'PY'
import json
import sys
import jsonschema
schema = json.load(open(sys.argv[1], encoding="utf-8"))
data = json.load(open(sys.argv[2], encoding="utf-8"))
jsonschema.validate(data, schema)
PY
fi

rm .gitattributes
"$GIT_NEST" doctor --offline >doctor_warn.out
assert_file_contains doctor_warn.out "W	gitattributes"
assert_exit_code 1 "$GIT_NEST" doctor --offline --exit-code >/dev/null 2>&1

describe_result "The command doctor health behavior matched the expected command output and repository state."
