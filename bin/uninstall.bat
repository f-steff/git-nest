@echo off
rem ===========================================================================
rem git-nest uninstaller for Windows (cmd.exe)
rem
rem Removes a git-nest installation made by install.bat and undoes its PATH
rem configuration.
rem
rem Usage:
rem   uninstall.bat [--prefix DIR] [--remove-path user|current|system]
rem
rem   --prefix DIR      Remove the installation under DIR (default:
rem                     %LOCALAPPDATA%\Programs\git-nest, matching
rem                     install.bat's default).
rem   --remove-path     Remove DIR\bin from PATH:
rem                       user    - permanently for this user (setx, HKCU; default,
rem                                 matching install.bat's --add-path user)
rem                       current - only in this shell session
rem                       system  - system-wide (HKLM; elevated prompt required)
rem ===========================================================================

setlocal enabledelayedexpansion

rem Capture the script location BEFORE any shift so %~dp0 stays valid.
set "SCRIPT_DIR=%~dp0"

set "PREFIX=%LOCALAPPDATA%\Programs\git-nest"
set "REMOVE_PATH=user"

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--prefix" (
    set "PREFIX=%~2"
    shift
    shift
    goto parse
)
if /i "%~1"=="--remove-path" (
    if /i "%~2"=="user" (
        set "REMOVE_PATH=user"
        shift
        shift
        goto parse
    )
    if /i "%~2"=="current" (
        set "REMOVE_PATH=current"
        shift
        shift
        goto parse
    )
    if /i "%~2"=="system" (
        set "REMOVE_PATH=system"
        shift
        shift
        goto parse
    )
    rem Bare --remove-path with no mode: default to user.
    set "REMOVE_PATH=user"
    shift
    goto parse
)
if /i "%~1"=="--help" goto help
echo uninstall.bat: unknown argument: %~1
exit /b 2
:parsed

set "DEST=%PREFIX%\bin"

if not exist "%DEST%\git_nest.sh" (
    echo uninstall.bat: no git-nest installation found at %DEST%
    exit /b 1
)

echo Removing git-nest from %PREFIX%
rmdir /s /q "%DEST%"

rem Remove staged content (man pages, docs, skill) if present.
if exist "%PREFIX%\share" rmdir /s /q "%PREFIX%\share"

rem Remove the now-empty prefix directory if nothing remains.
rd "%PREFIX%" 2>nul

rem --- PATH removal (default: user, matching install.bat's --add-path user) ---
if /i "%REMOVE_PATH%"=="current" (
    rem Strip DEST; from the current session PATH.
    set "NEWPATH="
    for %%P in ("%PATH:;=" "%") do (
        if /i not "%%~P"=="%DEST%" set "NEWPATH=!NEWPATH!;%%~P"
    )
    if defined NEWPATH set "NEWPATH=!NEWPATH:~1!"
    set "PATH=!NEWPATH!"
    echo   removed %DEST% from the PATH of this shell session
    exit /b 0
)

if /i "%REMOVE_PATH%"=="system" (
    rem Strip DEST; from the system PATH (HKLM). Requires elevation.
    powershell -NoProfile -Command "$d='%DEST%'; $p=[Environment]::GetEnvironmentVariable('Path','Machine'); $n=($p -split ';' | Where-Object { $_ -and $_ -ne $d }) -join ';'; if ($n -ne $p) { [Environment]::SetEnvironmentVariable('Path',$n,'Machine'); Write-Output 'removed from system PATH' } else { Write-Output 'not on system PATH' }"
    exit /b 0
)

rem Default: user PATH (HKCU).
powershell -NoProfile -Command "$d='%DEST%'; $p=[Environment]::GetEnvironmentVariable('Path','User'); $n=($p -split ';' | Where-Object { $_ -and $_ -ne $d }) -join ';'; if ($n -ne $p) { [Environment]::SetEnvironmentVariable('Path',$n,'User'); Write-Output 'removed from user PATH' } else { Write-Output 'not on user PATH' }"
exit /b 0

:help
echo git-nest uninstaller for Windows
echo.
echo   uninstall.bat [--prefix DIR] [--remove-path user^|current^|system]
echo.
echo   --prefix DIR         Remove the installation under DIR (default:
echo                        %%LOCALAPPDATA%%\Programs\git-nest)
echo   --remove-path user   Remove DIR\bin from the user PATH (default)
echo   --remove-path current  Remove DIR\bin from the current shell session
echo   --remove-path system   Remove DIR\bin from the system PATH (elevated)
exit /b 0
