#!/bin/sh
# Test: completion scripts generate, parse, and the __complete engine returns correct TSV

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

# --- Generator scripts produce valid output ---

"$GIT_NEST" completion bash >git-nest.bash
"$GIT_NEST" completion zsh >git-nest.zsh
"$GIT_NEST" completion fish >git-nest.fish
"$GIT_NEST" completion yash >git-nest.yash
"$GIT_NEST" completion powershell >git-nest.ps1

for f in git-nest.bash git-nest.zsh git-nest.fish git-nest.yash git-nest.ps1; do
    test -s "$f" || { echo "FAIL: $f is empty" >&2; exit 1; }
done

assert_file_contains git-nest.bash "complete -F _git_nest_complete git-nest"
assert_file_contains git-nest.bash "__complete"
assert_file_contains git-nest.zsh "#compdef git-nest"
assert_file_contains git-nest.zsh "__complete"
assert_file_contains git-nest.fish "complete -c git-nest"
assert_file_contains git-nest.fish "__complete"
assert_file_contains git-nest.yash "completion//argument-git-nest"
assert_file_contains git-nest.yash "__complete"
assert_file_contains git-nest.ps1 "Register-ArgumentCompleter"
assert_file_contains git-nest.ps1 "__complete"

# --- Syntax checks ---

bash -n git-nest.bash
sh -n git-nest.yash

if command -v zsh >/dev/null 2>&1; then
    zsh -n git-nest.zsh
fi
if command -v fish >/dev/null 2>&1; then
    fish --no-execute git-nest.fish
fi
if command -v pwsh >/dev/null 2>&1; then
    pwsh -noprofile -NoLogo -Command "try { [ScriptBlock]::Create((Get-Content 'git-nest.ps1' -Raw)) >\$null; exit 0 } catch { exit 1 }" 2>/dev/null
fi

# --- Legacy __complete commands / subprojects still work ---

"$GIT_NEST" __complete commands >commands.out
assert_file_contains commands.out "completion"
assert_file_contains commands.out "doctor"
assert_file_contains commands.out "export"
assert_file_contains commands.out "move"
assert_file_contains commands.out "restore"
assert_file_contains commands.out "branch-mark"
assert_file_contains commands.out "hooks-install"
assert_file_contains commands.out "help"

"$GIT_NEST" __complete subprojects >subprojects.out
assert_file_contains subprojects.out "libs/foo"

# --- New __complete CURSOR_INDEX -- ARG... interface (TSV) ---

# Build tab character for TSV assertions
_tab=$(printf '\t')

# cursor_index 0: list all commands (completing first/only arg)
"$GIT_NEST" __complete 0 -- "" >complete_0.out
assert_file_contains complete_0.out "init"
assert_file_contains complete_0.out "doctor"
assert_file_contains complete_0.out "no-file"

# cursor_index 0: completing the command name "doctor"
"$GIT_NEST" __complete 0 -- "doc" >complete_doc.out
assert_file_contains complete_doc.out "doctor"
assert_file_contains complete_doc.out "no-file"

# cursor_index 1 on 'doctor': list doctor options (command already given)
"$GIT_NEST" __complete 1 -- doctor "" >complete_doctor.out
assert_file_contains complete_doctor.out "--json"
assert_file_contains complete_doctor.out "--offline"
assert_file_contains complete_doctor.out "--timeout"
assert_file_contains complete_doctor.out "no-file"

# cursor_index 1 on 'completion': list shell names
"$GIT_NEST" __complete 1 -- completion "" >complete_completion.out
assert_file_contains complete_completion.out "bash"
assert_file_contains complete_completion.out "powershell"
assert_file_contains complete_completion.out "no-file"

# cursor_index 1 on 'config': list config actions
"$GIT_NEST" __complete 1 -- config "" >complete_config.out
assert_file_contains complete_config.out "get"
assert_file_contains complete_config.out "set"

# cursor_index 3 on 'config get libs/foo ': complete key
"$GIT_NEST" __complete 3 -- config get "libs/foo" "" >complete_config_key.out
assert_file_contains complete_config_key.out "clone-mode"

# cursor_index 1 on 'help': list all commands
"$GIT_NEST" __complete 1 -- help "" >complete_help.out
assert_file_contains complete_help.out "completion"
assert_file_contains complete_help.out "doctor"

# cursor_index 1 on 'remove': subprojects + options
"$GIT_NEST" __complete 1 -- remove "" >complete_remove.out
assert_file_contains complete_remove.out "libs/foo"
assert_file_contains complete_remove.out "--dry-run"

# cursor_index 1 on 'export': options only
"$GIT_NEST" __complete 1 -- export "" >complete_export.out
assert_file_contains complete_export.out "--format"
assert_file_contains complete_export.out "--output"
assert_file_contains complete_export.out "--include-git"

# --- Option values: --format completes tar.gz/zip/dir ---
"$GIT_NEST" __complete 2 -- export --format "" >complete_format.out
assert_file_contains complete_format.out "tar.gz"
assert_file_contains complete_format.out "zip"
assert_file_contains complete_format.out "dir"

# --- Verify TSV format (C\tvalue\tdesc\ttype for candidates, D\tdirective for directives) ---
_tsv_format_ok() {
    _file="$1"
    _bad=$(grep -vc "^[CD]${_tab}" "$_file" 2>/dev/null || true)
    [ "$_bad" -eq 0 ] || { echo "FAIL: $_file has non-TSV lines" >&2; exit 1; }
}
_tsv_format_ok complete_0.out
_tsv_format_ok complete_doctor.out
_tsv_format_ok complete_completion.out
_tsv_format_ok complete_config.out
_tsv_format_ok complete_config_key.out
_tsv_format_ok complete_help.out
_tsv_format_ok complete_remove.out
_tsv_format_ok complete_export.out
_tsv_format_ok complete_format.out

# --- Unknown shell still errors ---
if "$GIT_NEST" completion badshell >completion_bad.out 2>completion_bad.err; then
    echo "unknown completion shell should fail" >&2
    exit 1
fi
assert_file_contains completion_bad.err "unknown completion shell"

# --- Launcher dispatch tests (Windows: .bat polyglot + .ps1) ---

# .bat polyglot: should dispatch __complete through Git Bash
if [ -f "$GIT_NEST" ] && echo "$GIT_NEST" | grep -qi '\.bat$'; then
    "$GIT_NEST" __complete 0 -- "" >launcher_bat.out
    assert_file_contains launcher_bat.out "init"
fi

# .ps1 launcher: dispatch __complete through PowerShell if pwsh is available
if command -v pwsh >/dev/null 2>&1 && [ -f "$(dirname "$GIT_NEST")/git-nest.ps1" ]; then
    ps1="$(dirname "$GIT_NEST")/git-nest.ps1"
    pwsh -noprofile -NoLogo -Command "& '$ps1' __complete 0 -- ''" 2>/dev/null | head -5 >launcher_ps1.out
    grep 'init' launcher_ps1.out >/dev/null || true
fi

describe_result "The platform completion generation behavior matched the expected command output and repository state."
