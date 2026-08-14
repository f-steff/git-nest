#!/bin/sh
# Test: git-nest tui -- gate, help, completion, launcher markers, and a
# pty smoke test when `script` is available (non-Windows CI).

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_tui

# All capture files must land in the test workspace, not the repo root.
work=$(test_workspace command_tui)
mkdir -p "$work"
cd "$work"

test_step "Gate refuses non-TTY stdin with a clean message" "git-nest tui must refuse to start when stdin is not a terminal, print one message, and exit cleanly without touching the terminal."
run_fail "tui with redirected stdin exits nonzero" 2 -- sh -c '"$1" tui </dev/null >tui_gate.out 2>tui_gate.err' sh "$GIT_NEST"
assert_file_contains tui_gate.err "needs an interactive terminal"
assert_file_not_contains tui_gate.out "git-nest tui  -"
run_fail "tui with piped stdin exits nonzero" 2 -- sh -c 'echo | "$1" tui >tui_pipe.out 2>tui_pipe.err' sh "$GIT_NEST"
assert_file_contains tui_pipe.err "needs an interactive terminal"

test_step "tui appears in help and completion" "The command surface must list tui so users can discover it."
"$GIT_NEST" help >help_tui.out
assert_file_contains help_tui.out "tui"
assert_file_contains help_tui.out "Run an interactive terminal UI"
"$GIT_NEST" help tui >help_tui_cmd.out
assert_file_contains help_tui_cmd.out "git-nest help: tui"
assert_file_contains help_tui_cmd.out "Every action runs a fresh git-nest instance"
"$GIT_NEST" tui --help >help_flag.out
assert_file_contains help_flag.out "git-nest help: tui"
"$GIT_NEST" __complete commands >complete_commands.out
assert_file_contains complete_commands.out "tui"
"$GIT_NEST" __complete 1 -- tui "" >complete_tui.out
assert_file_contains complete_tui.out "no-file"

test_step "Launcher markers are set in the right halves" "git-nest.bat must set GIT_NEST_WIN_LAUNCHER=cmd inside its cmd.exe half (before the BATCH heredoc terminator), and git-nest.ps1 must set it to powershell before invoking bash."
bat=$(cat "$REPO_ROOT/bin/git-nest.bat")
assert_file_contains "$REPO_ROOT/bin/git-nest.bat" 'set "GIT_NEST_WIN_LAUNCHER=cmd"'
# The marker must appear before the BATCH heredoc terminator (cmd.exe half).
if printf '%s\n' "$bat" | grep -n 'set "GIT_NEST_WIN_LAUNCHER=cmd"' | cut -d: -f1 >bat_marker_line.txt &&
    printf '%s\n' "$bat" | grep -n '^BATCH' | cut -d: -f1 >bat_batch_line.txt; then
    marker_line=$(cat bat_marker_line.txt)
    batch_line=$(cat bat_batch_line.txt)
    [ "$marker_line" -lt "$batch_line" ] || {
        printf 'UNEXPECTED RESULT: GIT_NEST_WIN_LAUNCHER marker is outside the cmd.exe half of git-nest.bat\n' >&2
        exit 1
    }
fi
assert_file_contains "$REPO_ROOT/bin/git-nest.ps1" "\$env:GIT_NEST_WIN_LAUNCHER = 'powershell'"

test_step "Gate refuses the Windows launcher markers" "GIT_NEST_WIN_LAUNCHER=cmd or =powershell (set by the .bat/.ps1 launchers) must refuse with a mintty hint, because those launchers attach bash to the console where raw key reads never work."
run_fail "launcher marker cmd refused" 2 -- sh -c 'GIT_NEST_WIN_LAUNCHER=cmd "$1" tui </dev/null >marker_cmd.out 2>marker_cmd.err' sh "$GIT_NEST"
assert_file_contains marker_cmd.err "Git Bash (mintty) window"
assert_file_contains marker_cmd.err "cmd launcher"
assert_file_contains marker_cmd.err 'git-bash.exe'
assert_file_contains marker_cmd.err '--cd='
assert_file_contains marker_cmd.err '-c "git-nest tui"'
run_fail "launcher marker powershell refused" 2 -- sh -c 'GIT_NEST_WIN_LAUNCHER=powershell "$1" tui </dev/null >marker_ps.out 2>marker_ps.err' sh "$GIT_NEST"
assert_file_contains marker_ps.err "powershell launcher"
assert_file_contains marker_ps.err "PowerShell:"

test_step "pty smoke test (only where script exists)" "Under a pty, the TUI must start, render its header, and quit on q. Skipped on Windows Git Bash (no script/expect)."
if command -v script >/dev/null 2>&1; then
    pty_outer="$work/pty-outer"
    make_repo "$pty_outer"
    cd "$pty_outer"
    "$GIT_NEST" init >/dev/null
    printf 'q' | script -qec "stty rows 24 cols 100; \"$GIT_NEST_REAL\" tui" /dev/null >tui_pty.out 2>&1 || true
    if grep -q "git-nest tui" tui_pty.out; then
        :
    else
        # Strip ANSI escapes and retry; the header may be escape-wrapped.
        sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' tui_pty.out | grep -q "git-nest tui" || {
            printf 'UNEXPECTED RESULT: pty run did not render the TUI header\n' >&2
            exit 1
        }
    fi
    assert_file_contains tui_pty.out "git-nest version"
else
    echo "SKIP pty smoke test: no script command on this platform"
fi

describe_result "git-nest tui gates cleanly on non-TTY input, is discoverable in help/completion, sets launcher markers in the correct halves, and renders under a pty where script is available."
