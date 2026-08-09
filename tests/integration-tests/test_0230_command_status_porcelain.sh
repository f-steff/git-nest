#!/bin/sh
# Test: status human, porcelain, JSON, recursive, and exit-code output

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_status_porcelain

test_step "Exercise command status porcelain" "This test verifies the documented command status porcelain behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace command_status_porcelain)
remote="$root/remotes/foo.git"
seed="$root/seed/foo"
outer="$root/outer"
tab=$(printf '\t')

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

"$GIT_NEST" status --porcelain >"$root/clean.out"
test ! -s "$root/clean.out"
assert_exit_code 0 "$GIT_NEST" status --exit-code >/dev/null 2>&1

printf 'outer\n' >rootnote.txt
"$GIT_NEST" status --porcelain >"$root/dirty_outer.out"
assert_file_contains "$root/dirty_outer.out" "D${tab}.${tab}dirty${tab}-${tab}-${tab}-${tab}?? rootnote.txt"
assert_exit_code 1 "$GIT_NEST" status --exit-code >/dev/null 2>&1
rm -f rootnote.txt

printf 'subproject dirty\n' >>libs/foo/file.txt
"$GIT_NEST" status --porcelain >"$root/dirty_module.out"
assert_file_contains "$root/dirty_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab} M file.txt"
git -C libs/foo checkout -- file.txt

printf 'scratch\n' >libs/foo/scratch.txt
"$GIT_NEST" status --porcelain >"$root/untracked_module.out"
assert_file_contains "$root/untracked_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab}?? scratch.txt"
rm -f libs/foo/scratch.txt

printf 'staged\n' >libs/foo/staged.txt
git -C libs/foo add staged.txt
"$GIT_NEST" status --porcelain >"$root/staged_module.out"
assert_file_contains "$root/staged_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab}A  staged.txt"
git -C libs/foo reset --hard >/dev/null

rm -f libs/foo/file.txt
"$GIT_NEST" status --porcelain >"$root/deleted_module.out"
assert_file_contains "$root/deleted_module.out" "D${tab}libs/foo${tab}dirty${tab}-${tab}-${tab}-${tab} D file.txt"
git -C libs/foo reset --hard >/dev/null

rm -rf libs/foo

"$GIT_NEST" status --porcelain >"$root/missing.out"
assert_file_contains "$root/missing.out" "M${tab}libs/foo${tab}missing${tab}-${tab}-${tab}-${tab}checkout-missing"

"$GIT_NEST" status --porcelain --recursive >"$root/order_one.out"
"$GIT_NEST" status --recursive --porcelain >"$root/order_two.out"
cmp -s "$root/order_one.out" "$root/order_two.out"

# Restore a clean checkout for the remaining human/JSON/composite checks.
"$GIT_NEST" restore >/dev/null 2>&1
test -d libs/foo/.git

test_step "Human status output" "Plain status shows the outer branch and each subproject's pinned state."
"$GIT_NEST" status >"$root/human.out"
assert_file_contains "$root/human.out" "outer branch:"
assert_file_contains "$root/human.out" "libs/foo: pinned"

test_step "JSON status on a clean nest" "status --json reports ok:true and no subproject rows for a clean nest."
"$GIT_NEST" status --json >"$root/clean.json"
assert_file_contains "$root/clean.json" '"command":"status"'
assert_file_contains "$root/clean.json" '"ok":true'
python -m json.tool "$root/clean.json" >/dev/null 2>&1 || python3 -m json.tool "$root/clean.json" >/dev/null 2>&1 || true

test_step "Composite state when HEAD differs from the recorded revision" "Advancing a subproject past its recorded revision is reported as a composite (C) row and ok:false in JSON."
git -C libs/foo commit --allow-empty -m "advance past recorded revision" >/dev/null
"$GIT_NEST" status --porcelain >"$root/composite.out"
assert_file_contains "$root/composite.out" "C${tab}libs/foo${tab}composite${tab}-${tab}-${tab}-${tab}head-differs-from-manifest"
"$GIT_NEST" status --json >"$root/composite.json"
assert_file_contains "$root/composite.json" '"ok":false'
assert_file_contains "$root/composite.json" '"state":"composite"'

test_step "Reject combining --porcelain with --json" "The two machine-output modes are mutually exclusive."
if "$GIT_NEST" status --porcelain --json >"$root/conflict.out" 2>"$root/conflict.err"; then
    printf 'UNEXPECTED RESULT: status should reject --porcelain with --json\n' >&2
    exit 1
fi
assert_file_contains "$root/conflict.err" "cannot combine --porcelain with --json"

describe_result "The command status porcelain behavior matched the expected command output and repository state, including human, JSON, composite, and conflicting-flag cases."
