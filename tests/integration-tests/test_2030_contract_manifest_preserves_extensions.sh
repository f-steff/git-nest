#!/bin/sh
# Test: manifest rewrites preserve unknown extension keys

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
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$url" libs/one >/dev/null
cat >>.gitnest <<EOF

[extension "local"]
owner=kept
EOF
awk '
    /^\[subproject "libs\/one"\]$/ { print; print "x-extension=one"; next }
    { print }
' .gitnest >.gitnest.tmp
mv .gitnest.tmp .gitnest
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "initial workspace" >/dev/null

test_step "Move a subproject with extension keys present" "manifest rewrites should preserve unknown sections and unknown keys where practical."
run_ok "subproject path moved" -- "$GIT_NEST" mv libs/one components/one
assert_file_contains .gitnest '[subproject "components/one"]'
assert_file_contains .gitnest 'x-extension=one'
assert_file_contains .gitnest '[extension "local"]'
assert_file_contains .gitnest 'owner=kept'
describe_result "the manifest rewrite preserved local extension metadata while renaming the subproject section."
