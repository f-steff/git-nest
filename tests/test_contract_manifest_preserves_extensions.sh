#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_manifest_preserves_extensions

root=$(test_workspace contract_manifest_preserves_extensions)
remote="$root/remotes/one.git"
seed="$root/seed/one"
outer="$root/outer"
url="file://$remote"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$url" libs/one >/dev/null
cat >>.gitlego <<EOF

[extension "local"]
owner=kept
EOF
awk '
    /^\[subproject "libs\/one"\]$/ { print; print "x-extension=one"; next }
    { print }
' .gitlego >.gitlego.tmp
mv .gitlego.tmp .gitlego
git add .gitlego .gitignore .gitattributes
git commit -m "initial workspace" >/dev/null

test_step "Move a subproject with extension keys present" "manifest rewrites should preserve unknown sections and unknown keys where practical."
run_ok "subproject path moved" -- "$GIT_LEGO" mv libs/one components/one
assert_file_contains .gitlego '[subproject "components/one"]'
assert_file_contains .gitlego 'x-extension=one'
assert_file_contains .gitlego '[extension "local"]'
assert_file_contains .gitlego 'owner=kept'
describe_result "the manifest rewrite preserved local extension metadata while renaming the subproject section."
