#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin completion_command

work=$(test_workspace completion_command)
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
assert_file_contains commands.out "export"
assert_file_contains commands.out "sync"

"$GIT_LEGO" __complete subprojects >subprojects.out
assert_file_contains subprojects.out "libs/foo"

if "$GIT_LEGO" completion powershell >completion_bad.out 2>completion_bad.err; then
    echo "unknown completion shell should fail" >&2
    exit 1
fi
assert_file_contains completion_bad.err "unknown completion shell"
