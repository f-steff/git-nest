#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_option_snapshot_base_missing_target

root=$(test_workspace command_option_snapshot_base_missing_target)
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

test_step "Create local subproject work with an unresolvable target branch" "snapshot must not guess a base commit when target_branch is wrong."
git -C libs/foo checkout -b BASE-1 >/dev/null
printf 'base\n' >>libs/foo/file.txt
git -C libs/foo add file.txt
git -C libs/foo commit -m "BASE-1 local work" >/dev/null
base=$(git -C libs/foo rev-parse HEAD^)
grep -v '^target_branch=' .gitlego >.gitlego.no-target
awk '
    /^\[subproject "libs\/foo"\]$/ { in_section=1 }
    in_section && /^repo=/ && !done { print; print "target_branch=missing-target"; done=1; next }
    /^\[/ && $0 != "[subproject \"libs/foo\"]" { in_section=0 }
    { print }
' .gitlego.no-target >.gitlego.tmp
rm -f .gitlego.no-target
mv .gitlego.tmp .gitlego
cp .gitlego before_base_failure

test_step "Run snapshot without an explicit base" "the command should fail and leave the manifest unchanged."
run_fail "missing target branch rejected before manifest mutation" any -- sh -c '"$1" snapshot >base_fail.out 2>base_fail.err' sh "$GIT_LEGO"
assert_file_contains base_fail.err "cannot calculate base revision for libs/foo"
cmp .gitlego before_base_failure >/dev/null

test_step "Run snapshot with --base" "the explicit base override gives the command enough information to record pending state."
run_ok "snapshot recorded the supplied base revision" -- "$GIT_LEGO" snapshot --base libs/foo="$base"
assert_file_contains .gitlego "base_revision=$base"
describe_result "snapshot refused unresolved target_branch, then succeeded with an explicit --base override."
