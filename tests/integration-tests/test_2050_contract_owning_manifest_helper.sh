#!/bin/sh
# Test: the internal owning-manifest helper resolves the correct nest root

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_owning_manifest_helper

test_step "Exercise contract owning manifest helper" "This test verifies the documented contract owning manifest helper behavior and fails if command output or repository state differs from the expected result."

root=$(test_workspace contract_owning_manifest_helper)
outer="$root/outer"
outside="$root/outside"

make_repo "$outer"
mkdir -p "$outside"

cd "$outer"
"$GIT_NEST" init >/dev/null
mkdir -p src/deep nested/sub
printf 'content\n' >src/deep/file.txt
git add .gitnest .gitignore .gitattributes NEST_README.md src/deep/file.txt
git commit -m "outer project" >/dev/null

# cd -P resolves through macOS symlinks (/var -> /private/var, /tmp -> /private/tmp)
# so the test's computed path matches the physical path returned by
# canonical_start_dir_for_path() which also uses cd -P.
outer_manifest=$(CDPATH= cd -P -- "$outer" && pwd)/.gitnest

[ "$("$GIT_NEST" __owning-manifest)" = "$outer_manifest" ] || {
    echo "owning manifest from project root should be the root manifest" >&2
    exit 1
}

from_subdir=$(cd src/deep && "$GIT_NEST" __owning-manifest)
[ "$from_subdir" = "$outer_manifest" ] || {
    echo "owning manifest from a subdirectory should be the root manifest" >&2
    exit 1
}

from_file=$("$GIT_NEST" __owning-manifest src/deep/file.txt)
[ "$from_file" = "$outer_manifest" ] || {
    echo "owning manifest from an explicit file path should use the file's directory" >&2
    exit 1
}

cat >nested/.gitnest <<EOF
# git-nest manifest

[project]
version=1
EOF
# Use cd -P for the same symlink-resolution reason as above.
nested_manifest=$(CDPATH= cd -P -- "$outer/nested" && pwd)/.gitnest
from_nested=$(cd nested/sub && "$GIT_NEST" __owning-manifest)
[ "$from_nested" = "$nested_manifest" ] || {
    echo "owning manifest inside nested territory should be the nested manifest" >&2
    exit 1
}

if (cd "$root" && ln -s outer/src/deep linked-deep) >/dev/null 2>&1 && [ -L "$root/linked-deep" ]; then
    from_symlink=$("$GIT_NEST" __owning-manifest "$root/linked-deep")
    [ "$from_symlink" = "$outer_manifest" ] || {
        echo "owning manifest from a symlink into the project should resolve to the project manifest" >&2
        exit 1
    }
fi

if "$GIT_NEST" __owning-manifest "$outer/missing" >missing.out 2>missing.err; then
    echo "owning manifest should refuse missing explicit paths" >&2
    exit 1
fi
assert_file_contains missing.err 'does not exist'

if (cd "$outside" && "$GIT_NEST" __owning-manifest >outside.out 2>outside.err); then
    echo "owning manifest should fail outside a git-nest project" >&2
    exit 1
fi
assert_file_contains "$outside/outside.err" 'not inside a git-nest project'

describe_result "The contract owning manifest helper behavior matched the expected command output and repository state."
