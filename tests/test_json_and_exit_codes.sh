#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin json_and_exit_codes

root=$(test_workspace json_and_exit_codes)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

"$GIT_LEGO" status --json >status.json
"$GIT_LEGO" verify --json >verify.json || test "$?" = "1"
"$GIT_LEGO" outdated --json >outdated.json
"$GIT_LEGO" no-pending --json >no_pending.json
"$GIT_LEGO" status --recursive --json >status_recursive.json
"$GIT_LEGO" verify --recursive --json-pretty >verify_recursive.json || test "$?" = "1"
"$GIT_LEGO" outdated --recursive --json >outdated_recursive.json

for file in status.json verify.json outdated.json no_pending.json status_recursive.json verify_recursive.json outdated_recursive.json; do
    python -m json.tool "$file" >/dev/null 2>&1 || python3 -m json.tool "$file" >/dev/null
    assert_file_contains "$file" '"version"'
    assert_file_contains "$file" '"subprojects"'
    if python - <<PY >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec("jsonschema") else 1)
PY
    then
        python - "$REPO_ROOT/schemas/git-lego-output-v1.schema.json" "$file" <<'PY'
import json
import sys
import jsonschema
schema = json.load(open(sys.argv[1], encoding="utf-8"))
data = json.load(open(sys.argv[2], encoding="utf-8"))
jsonschema.validate(data, schema)
PY
    fi
done
assert_file_contains status_recursive.json '"recursive":true'
assert_file_contains verify_recursive.json '"recursive": true'
assert_file_contains outdated_recursive.json '"command":"outdated"'

printf 'dirty\n' >rootnote.txt
assert_exit_code 1 "$GIT_LEGO" status --exit-code >/dev/null 2>&1
"$GIT_LEGO" status --porcelain >status_porcelain.out
test "$(awk -F '\t' 'NF { print NF }' status_porcelain.out | sort -u)" = "7"
rm -f rootnote.txt

printf 'second\n' >>"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit -m "second" >/dev/null
git -C "$seed" push origin main >/dev/null
assert_exit_code 1 "$GIT_LEGO" outdated >/dev/null 2>&1
"$GIT_LEGO" outdated --porcelain >outdated_porcelain.out || test "$?" = "1"
test "$(awk -F '\t' 'NF { print NF }' outdated_porcelain.out | sort -u)" = "7"

git -C libs/foo checkout -b JSON-100-pending >/dev/null
printf 'pending\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "JSON-100 pending" >/dev/null
"$GIT_LEGO" upload >/dev/null
assert_exit_code 1 "$GIT_LEGO" no-pending >/dev/null 2>&1
"$GIT_LEGO" no-pending --json >pending.json || test "$?" = "1"
assert_file_contains pending.json '"command":"no-pending"'
assert_file_contains pending.json '"code":"P"'

assert_exit_code 2 "$GIT_LEGO" no-such-command >/dev/null 2>&1
empty="$root/empty"
mkdir -p "$empty"
cd "$empty"
assert_exit_code 3 "$GIT_LEGO" status >/dev/null 2>&1

git_failure="$root/git_failure"
mkdir -p "$git_failure"
make_repo "$git_failure"
cd "$git_failure"
"$GIT_LEGO" init >/dev/null
assert_exit_code 5 "$GIT_LEGO" add "$root/no-such-remote.git" libs/missing >/dev/null 2>&1
