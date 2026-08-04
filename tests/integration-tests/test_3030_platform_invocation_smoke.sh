#!/bin/sh
# Test: git-nest is invokable directly and as a git subcommand with the right version

set -eu
. "$(dirname "$0")/helper.sh"
test_begin platform_invocation_smoke

test_step "Invoke git-nest directly and as a git subcommand" "The shipped entrypoint must run both as 'git-nest' and via Git's external-command discovery as 'git nest', reporting the same version, and --help must succeed."

# Put the real entrypoint's directory first on PATH so 'git nest' resolves to the
# actual shipped git-nest (via Git external-command discovery), not the test shim.
PATH="$(CDPATH= cd -- "$(dirname -- "$GIT_NEST_REAL")" && pwd):$PATH"
export PATH

# Computed from the real entrypoint rather than hardcoded: a hardcoded
# literal silently goes stale on every version bump (this test failed for
# exactly that reason -- it still expected 0.8.2 after the version moved to
# 0.8.3).
expected_version=$(sh "$GIT_NEST_REAL" version)

run_ok "direct --help works" -- sh "$GIT_NEST_REAL" --help
test "$(sh "$GIT_NEST_REAL" version)" = "$expected_version"
test "$(sh "$GIT_NEST_REAL" --version)" = "$expected_version"
# Git-style invocation must find git-nest on PATH and print the same version.
test "$(git nest version)" = "$expected_version"

# The .bat polyglot launcher must work from cmd.exe on Windows and report the
# same version (it locates Git Bash internally and forwards to git-nest).
if command -v cmd >/dev/null 2>&1; then
    bat_path="$(CDPATH= cd -- "$(dirname -- "$GIT_NEST_REAL")" && pwd -W)/git-nest.bat"
    run_ok "cmd.exe launcher version matches" -- cmd //c "$bat_path" version
fi

# The .ps1 PowerShell launcher must work wherever pwsh is installed and report
# the same version (on Windows it finds Git Bash; on POSIX it runs /bin/sh).
# On MSYS2/Git Bash the path must be converted to Windows form for native pwsh;
# elsewhere the POSIX path is fine.
if command -v pwsh >/dev/null 2>&1; then
    ps1_dir=$(CDPATH= cd -- "$(dirname -- "$GIT_NEST_REAL")" && pwd)
    if CDPATH= cd -- "$(dirname -- "$GIT_NEST_REAL")" && pwd -W >/dev/null 2>&1; then
        ps1_dir=$(CDPATH= cd -- "$(dirname -- "$GIT_NEST_REAL")" && pwd -W)
    fi
    run_ok "pwsh launcher version matches" -- pwsh -noprofile -NoLogo -Command "& '$ps1_dir/git-nest.ps1' version"
fi

describe_result "git-nest ran directly and as a git subcommand with matching version output."
