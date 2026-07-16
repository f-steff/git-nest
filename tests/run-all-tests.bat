: <<'BATCH'
@echo off
rem Polyglot test-suite launcher. cmd.exe executes this batch section, while
rem POSIX shells skip it through the heredoc marker above and use the shell
rem fallback below. The actual test logic stays in run-all-tests.sh.
setlocal EnableExtensions

rem Find Git Bash next to git.exe so Windows users do not need sh.exe on PATH.
set "BASH_EXE="
for /f "delims=" %%G in ('where git 2^>nul') do (
    if not defined BASH_EXE (
        for %%B in ("%%~dpG..\bin\bash.exe") do (
            if exist "%%~fB" set "BASH_EXE=%%~fB"
        )
    )
)

if not defined BASH_EXE (
    echo Error: Could not locate Git Bash from git.exe on PATH.
    exit /b 3
)

rem Run the canonical shell suite next to this wrapper. All arguments are
rem forwarded unchanged to run-all-tests.sh, including the commands list, only
rem <ids>, except <ids>, and help, and the options --verbose, --stop-on-fail,
rem --no-log, and --log FILE.
set "SCRIPT=%~dp0run-all-tests.sh"
if not exist "%SCRIPT%" (
    echo Error: Could not locate tests\run-all-tests.sh next to this wrapper.
    exit /b 2
)

set "SCRIPT=%SCRIPT:\=/%"
"%BASH_EXE%" --noprofile --norc "%SCRIPT%" %*
exit /b %ERRORLEVEL%
BATCH

#!/usr/bin/env bash
# Shell fallback for users who execute this polyglot file from Git Bash. Keep
# all suite behavior in run-all-tests.sh so Windows and POSIX entrypoints stay aligned.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/run-all-tests.sh" "$@"
