#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin platform_completion_generation

test_step "Exercise platform completion generation" "This test verifies the documented platform completion generation behavior and fails if command output or repository state differs from the expected result."

work=$(test_workspace platform_completion_generation)
remote="$work/remotes/foo.git"
seed="$work/seed/foo"
outer="$work/outer"

mkdir -p "$work/remotes" "$work/seed"
make_bare_remote "$remote" "$seed"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "$remote" libs/foo >/dev/null

"$GIT_NEST" completion bash >git-nest.bash
"$GIT_NEST" completion zsh >git-nest.zsh
"$GIT_NEST" completion fish >git-nest.fish

test -s git-nest.bash
test -s git-nest.zsh
test -s git-nest.fish

assert_file_contains git-nest.bash "complete -F _git_nest_complete git-nest"
assert_file_contains git-nest.bash "git-nest __complete subprojects"
assert_file_contains git-nest.zsh "#compdef git-nest"
assert_file_contains git-nest.fish "complete -c git-nest"

bash -n git-nest.bash
if command -v zsh >/dev/null 2>&1; then
    zsh -n git-nest.zsh
fi
if command -v fish >/dev/null 2>&1; then
    fish --no-execute git-nest.fish
fi

"$GIT_NEST" __complete commands >commands.out
assert_file_contains commands.out "completion"
assert_file_contains commands.out "doctor"
assert_file_contains commands.out "export"
assert_file_contains commands.out "sync"
assert_file_contains git-nest.bash "--dry-run"
assert_file_contains git-nest.bash "--offline --timeout --exit-code"
assert_file_contains git-nest.zsh "doctor)"
assert_file_contains git-nest.fish "__fish_seen_subcommand_from doctor"

"$GIT_NEST" __complete subprojects >subprojects.out
assert_file_contains subprojects.out "libs/foo"

if "$GIT_NEST" completion powershell >completion_bad.out 2>completion_bad.err; then
    echo "unknown completion shell should fail" >&2
    exit 1
fi
assert_file_contains completion_bad.err "unknown completion shell"

describe_result "The platform completion generation behavior matched the expected command output and repository state."
