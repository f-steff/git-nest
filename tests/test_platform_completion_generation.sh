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
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$remote" libs/foo >/dev/null

"$GIT_LEGO" completion bash >git-lego.bash
"$GIT_LEGO" completion zsh >git-lego.zsh
"$GIT_LEGO" completion fish >git-lego.fish

test -s git-lego.bash
test -s git-lego.zsh
test -s git-lego.fish

assert_file_contains git-lego.bash "complete -F _git_lego_complete git-lego"
assert_file_contains git-lego.bash "git-lego __complete subprojects"
assert_file_contains git-lego.zsh "#compdef git-lego"
assert_file_contains git-lego.fish "complete -c git-lego"

bash -n git-lego.bash
if command -v zsh >/dev/null 2>&1; then
    zsh -n git-lego.zsh
fi
if command -v fish >/dev/null 2>&1; then
    fish --no-execute git-lego.fish
fi

"$GIT_LEGO" __complete commands >commands.out
assert_file_contains commands.out "completion"
assert_file_contains commands.out "doctor"
assert_file_contains commands.out "export"
assert_file_contains commands.out "sync"
assert_file_contains git-lego.bash "--dry-run"
assert_file_contains git-lego.bash "--offline --timeout --exit-code"
assert_file_contains git-lego.zsh "doctor)"
assert_file_contains git-lego.fish "__fish_seen_subcommand_from doctor"

"$GIT_LEGO" __complete subprojects >subprojects.out
assert_file_contains subprojects.out "libs/foo"

if "$GIT_LEGO" completion powershell >completion_bad.out 2>completion_bad.err; then
    echo "unknown completion shell should fail" >&2
    exit 1
fi
assert_file_contains completion_bad.err "unknown completion shell"

describe_result "The platform completion generation behavior matched the expected command output and repository state."
