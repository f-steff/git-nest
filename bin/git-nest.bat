: <<'BATCH'
@echo off
rem Polyglot launcher for cmd.exe and sh/bash users. This lets the same file be
rem called from Windows batch contexts and cross-platform IDE build hooks while
rem still delegating behavior to the adjacent implementation file, bin\git-nest-main.sh
rem (which self-dispatches when run directly). The batch side only finds Git
rem Bash, converts the script path, and forwards all arguments.
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

set "SCRIPT=%~dp0git-nest-main.sh"
if not exist "%SCRIPT%" (
    set "SCRIPT="
    for /f "delims=" %%I in ('where git-nest-main.sh 2^>nul') do (
        if not defined SCRIPT set "SCRIPT=%%~fI"
    )
)

if not defined SCRIPT (
    echo Error: Could not locate git-nest-main.sh next to this wrapper or on PATH.
    exit /b 2
)

set "SCRIPT=%SCRIPT:\=/%"
set "GIT_NEST_WIN_LAUNCHER=cmd"
"%BASH_EXE%" --noprofile --norc "%SCRIPT%" %*
exit /b %ERRORLEVEL%
BATCH

#!/usr/bin/env bash
# Bash fallback for environments that execute this polyglot wrapper as a shell
# script instead of a batch file. This keeps one command path usable from IDE
# post-build hooks on Windows, Linux, and macOS while still routing all behavior
# through the adjacent implementation file, which self-dispatches.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/git-nest-main.sh" "$@"
