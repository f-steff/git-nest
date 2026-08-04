: <<'BATCH'
@echo off
rem Polyglot launcher for cmd.exe and sh/bash users. Delegates to the
rem adjacent shell runner, tests\unit-tests\run-all-tests.sh, through Git Bash.
rem
rem Keeps one command path usable from IDE post-build hooks on Windows,
rem Linux, and macOS while still routing behavior through the canonical
rem POSIX runner.
setlocal EnableExtensions

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

set "SCRIPT=%~dp0run-all-tests.sh"
if not exist "%SCRIPT%" (
    echo Error: Could not locate run-all-tests.sh next to this wrapper.
    exit /b 2
)

set "SCRIPT=%SCRIPT:\=/%"
"%BASH_EXE%" --noprofile --norc "%SCRIPT%" %*
exit /b %ERRORLEVEL%
BATCH

#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/run-all-tests.sh" "$@"
