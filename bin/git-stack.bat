: <<'BATCH'
@echo off
rem Polyglot launcher for cmd.exe and sh/bash users. This lets the same file be
rem called from Windows batch contexts and cross-platform IDE build hooks while
rem still delegating behavior to the adjacent shell entrypoint, bin\git-stack.
rem If that file is not next to this wrapper, PATH is searched for git-stack.
rem The batch side otherwise only finds Git Bash, converts the script path, and
rem forwards all arguments.
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

set "SCRIPT=%~dp0git-stack"
if not exist "%SCRIPT%" (
    set "SCRIPT="
    for /f "delims=" %%I in ('where git-stack 2^>nul') do (
        if not defined SCRIPT set "SCRIPT=%%~fI"
    )
)

if not defined SCRIPT (
    echo Error: Could not locate git-stack next to this wrapper or on PATH.
    exit /b 2
)

set "SCRIPT=%SCRIPT:\=/%"
"%BASH_EXE%" --noprofile --norc "%SCRIPT%" %*
exit /b %ERRORLEVEL%
BATCH

#!/usr/bin/env bash
# Bash fallback for environments that execute this polyglot wrapper as a shell
# script instead of a batch file. This keeps one command path usable from IDE
# post-build hooks on Windows, Linux, and macOS while still routing all behavior
# through the canonical POSIX entrypoint next to it.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/git-stack" "$@"
