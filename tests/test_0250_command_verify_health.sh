#!/bin/sh
# Test: verify passes a clean nest and errors or warns on the documented problems, with JSON

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_verify_health

# verify is the workspace-integrity command. This exercises a clean pass and
# each failure/warning it is documented to detect, plus its exit code and JSON.
test_step "Exercise verify health checks" "verify must pass a clean nest, warn on dirty and unmanaged repositories, and error (nonzero) on missing checkouts, wrong remotes, revision drift, and unresolvable revisions, with matching JSON."

root=$(test_workspace command_verify_health)
remote_foo="$root/remotes/foo.git"
outer="$root/outer"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
# Use a file:// URL so the recorded manifest URL matches the origin Git stores
# (a bare filesystem path gets rewritten to a Windows path on Git for Windows).
foo_url="file://$remote_foo"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$foo_url" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null
recorded=$(git -C libs/foo rev-parse HEAD)

# --- Clean nest passes and exits 0 ---
test_step "A clean nest verifies" "verify reports success and exits 0."
run_capture "clean verify passes" clean.out clean.err -- "$GIT_NEST" verify
assert_file_contains clean.out "Project verified."

# --- Dirty subproject is a warning, not an error (still exits 0) ---
test_step "A dirty subproject warns but passes" "Uncommitted changes are a warning; verify still succeeds."
printf 'dirty\n' >>libs/foo/file.txt
run_capture "dirty verify warns and passes" dirty.out dirty.err -- "$GIT_NEST" verify
assert_file_contains dirty.err "uncommitted changes"
assert_file_contains dirty.out "Project verified."
git -C libs/foo checkout -- file.txt

# --- Unmanaged nested repository is a warning ---
test_step "An unmanaged nested repo warns" "A nested repo not in .gitnest is reported as a warning."
git clone "$remote_foo" libs/extra >/dev/null 2>&1
run_capture "unmanaged repo warns" unmanaged.out unmanaged.err -- "$GIT_NEST" verify
assert_file_contains unmanaged.err "unmanaged nested Git repository"
rm -rf libs/extra

# Helper: assert that verify fails (nonzero) and its stderr contains a message.
assert_verify_error() {
    label=$1
    expected=$2
    if "$GIT_NEST" verify >"$label.out" 2>"$label.err"; then
        printf 'UNEXPECTED RESULT: verify should have failed for %s\n' "$label" >&2
        exit 1
    fi
    assert_file_contains "$label.err" "$expected"
}

# --- Revision drift is an error ---
test_step "Revision drift fails verification" "A checkout whose HEAD differs from the recorded revision is an error."
git -C libs/foo commit --allow-empty -m "advance past recorded revision" >/dev/null
assert_verify_error drift "does not match revision"
git -C libs/foo checkout --quiet "$recorded"

# --- Wrong origin remote is an error ---
test_step "A wrong origin remote fails verification" "verify compares the checkout origin to the manifest URL."
git -C libs/foo remote set-url origin "https://example.invalid/wrong.git"
assert_verify_error remote "origin remote differs from manifest"
git -C libs/foo remote set-url origin "$foo_url"

# --- Missing checkout is an error ---
test_step "A missing checkout fails verification" "A recorded subproject with no checkout on disk is an error."
mv libs/foo "$root/foo-stash"
assert_verify_error missing "subproject checkout is missing"
mv "$root/foo-stash" libs/foo

# --- Unresolvable revision is an error, and JSON reports ok:false ---
test_step "An unresolvable revision fails verification and JSON reports it" "A manifest revision that does not exist errors, and verify --json returns ok:false with a populated errors array."
cp .gitnest .gitnest.bak
sed 's/^revision=.*/revision=0123456789012345678901234567890123456789/' .gitnest.bak >.gitnest
assert_verify_error unresolvable "is not resolvable"
if "$GIT_NEST" verify --json >verify.json 2>/dev/null; then
    printf 'UNEXPECTED RESULT: verify --json should exit nonzero on errors\n' >&2
    exit 1
fi
assert_file_contains verify.json '"command":"verify"'
assert_file_contains verify.json '"ok":false'
assert_file_contains verify.json 'is not resolvable'
python -m json.tool verify.json >/dev/null 2>&1 || python3 -m json.tool verify.json >/dev/null 2>&1 || true
# Restore the good manifest.
mv .gitnest.bak .gitnest

# --- Clean nest verifies via JSON with ok:true ---
test_step "JSON reports ok:true for a clean nest" "verify --json on a healthy nest returns ok:true and exits 0."
run_capture "json verify passes" okjson.out okjson.err -- "$GIT_NEST" verify --json
assert_file_contains okjson.out '"command":"verify"'
assert_file_contains okjson.out '"ok":true'

describe_result "verify passed a clean nest, warned on dirty and unmanaged repositories, errored on missing checkouts, wrong remotes, revision drift, and unresolvable revisions, and reported matching JSON and exit codes."
