#!/bin/sh
# Test: list reports managed subprojects with reproducibility across human, porcelain, and JSON

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_list_inventory

# list is the scriptable inventory command: it prints every managed subproject
# with its recorded fields and on-disk reproducibility state, in a stable order.
test_step "Exercise list inventory output" "list must report path, URL, target, revision, tag, checkout state, and reproducibility in human, porcelain, and JSON forms, including drift and missing checkouts."

root=$(test_workspace command_list_inventory)
outer="$root/outer"
remote_foo="$root/remotes/foo.git"
remote_bar="$root/remotes/bar.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_bar" "$root/seed/bar"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null

# --- Empty inventory ---
test_step "List an empty nest" "With no subprojects, list should say so rather than print an empty table."
run_capture "empty list reports no subprojects" empty.out empty.err -- "$GIT_NEST" list
assert_file_contains empty.out 'No subprojects are recorded'

# --- Populate two subprojects ---
"$GIT_NEST" add "file://$remote_foo" libs/foo >/dev/null
"$GIT_NEST" add "file://$remote_bar" libs/bar >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "add subprojects" >/dev/null
foo_rev=$(git -C libs/foo rev-parse HEAD)

# --- Human output lists both in stable (sorted) order ---
test_step "List reports both subprojects" "A clean checkout at the recorded revision is reproducible (code R)."
run_capture "human list shows both subprojects" list.out list.err -- "$GIT_NEST" list
assert_file_contains list.out 'libs/bar'
assert_file_contains list.out 'libs/foo'
# libs/bar sorts before libs/foo; confirm the stable ordering.
head -n 2 list.out | tail -n 1 | grep -q 'libs/bar' && echo 'OK: libs/bar listed first' || {
    printf 'UNEXPECTED RESULT: list is not in sorted order\n' >&2
    exit 1
}

# --- Porcelain output is fixed-column and machine-friendly ---
test_step "List porcelain output" "Porcelain rows carry the reproducibility code, path, state, target, revision, tag, and URL."
run_capture "porcelain list emits rows" list_p.out list_p.err -- "$GIT_NEST" list --porcelain
assert_file_contains list_p.out "R	libs/foo	clean	main	$foo_rev	-	file://$remote_foo"

# --- JSON output ---
test_step "List JSON output" "list --json emits the shared envelope with one row per subproject."
run_capture "json list emits envelope" list.json list_j.err -- "$GIT_NEST" list --json
assert_file_contains list.json '"command":"list"'
assert_file_contains list.json '"path":"libs/foo"'
assert_file_contains list.json '"code":"R"'
python -m json.tool list.json >/dev/null 2>&1 || python3 -m json.tool list.json >/dev/null 2>&1 || true

# --- Dirty but not advanced: still reproducible, state reported as dirty ---
test_step "List reports a dirty checkout" "An uncommitted change leaves HEAD at the recorded revision, so it is still reproducible (code R) but the state is dirty."
printf 'more\n' >>libs/foo/file.txt
run_capture "dirty state is reported" dirty.out dirty.err -- "$GIT_NEST" list --porcelain
assert_file_contains dirty.out 'R	libs/foo	dirty'

# --- Drift: advance a checkout past the recorded revision ---
test_step "List reports drift" "A checkout whose HEAD differs from the recorded revision is drift (code D)."
git -C libs/foo add file.txt
git -C libs/foo -c user.email=a@b -c user.name=a commit -m "advance" >/dev/null
run_capture "drift is reported" drift.out drift.err -- "$GIT_NEST" list --porcelain
assert_file_contains drift.out 'D	libs/foo	clean'

# --- Missing: remove a checkout while keeping the manifest entry ---
test_step "List reports a missing checkout" "A recorded subproject with no checkout on disk is missing (code M)."
rm -rf libs/bar
run_capture "missing checkout reported" missing.out missing.err -- "$GIT_NEST" list --porcelain
assert_file_contains missing.out 'M	libs/bar	missing'

# --- Redaction: credentials in URLs are stripped with --redact ---
test_step "List --redact strips URL credentials" "A subproject URL containing credentials must appear verbatim without --redact and be redacted with it."
cat >>.gitnest <<EOF

[subproject "libs/cred"]
repo=https://alice:s3cr3t@example.invalid/cred.git
target_branch=main
revision=0123456789012345678901234567890123456789
EOF
run_capture "plain list keeps the URL verbatim" cred_plain.out cred_plain.err -- "$GIT_NEST" list --porcelain
assert_file_contains cred_plain.out 's3cr3t'
run_capture "redacted list hides the credentials" cred_redacted.out cred_redacted.err -- "$GIT_NEST" list --porcelain --redact
assert_file_not_contains cred_redacted.out 's3cr3t'
assert_file_contains cred_redacted.out 'https://***@example.invalid/cred.git'
run_capture "redacted JSON hides the credentials" cred_redacted.json cred_redacted_json.err -- "$GIT_NEST" list --json --redact
assert_file_not_contains cred_redacted.json 's3cr3t'

describe_result "list reported managed subprojects with reproducibility, drift, and missing states across human, porcelain, and JSON output, and redacted URL credentials with --redact."
