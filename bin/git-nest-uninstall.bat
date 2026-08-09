@echo off
rem ===========================================================================
rem git-nest uninstaller for Windows (cmd.exe)
rem
rem Removes a git-nest installation and undoes its PATH configuration.
rem
rem The uninstaller is copied into the installed bin\ directory, which is
rem on PATH, so it is normally invoked directly:
rem
rem   git-nest-uninstall.bat                 (removes this installation)
rem   git-nest-uninstall.bat --prefix DIR    (custom prefix)
rem
rem   --prefix DIR      Remove the installation under DIR (default: the
rem                     installation this script lives in, or
rem                     %LOCALAPPDATA%\Programs\git-nest when run from the
rem                     source checkout).
rem   --remove-path     Remove DIR\bin from PATH:
rem                       user    - permanently for this user (setx, HKCU; default,
rem                                 matching git-nest-install.bat's --add-path user)
rem                       current - only in this shell session
rem                       system  - system-wide (HKLM; elevated prompt required)
rem ===========================================================================

setlocal enabledelayedexpansion

rem Capture the script location BEFORE any shift so %~dp0 stays valid.
set "SCRIPT_DIR=%~dp0"

set "PREFIX="
set "REMOVE_PATH=user"

rem Self-locate: when this script sits in an installed <prefix>\bin, the
rem default prefix is its own parent. When run from the source checkout
rem (which has AGENTS.md / .git), fall back to the installer default.
if exist "%SCRIPT_DIR%git-nest-main.sh" if not exist "%SCRIPT_DIR%..\AGENTS.md" if not exist "%SCRIPT_DIR%..\.git" (
    rem %%~fI resolves the .. so the prefix is a clean absolute path.
    for %%I in ("%SCRIPT_DIR%..") do set "PREFIX=%%~fI"
)
if "%PREFIX%"=="" set "PREFIX=%LOCALAPPDATA%\Programs\git-nest"

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
echo git-nest-uninstall.bat: unknown argument: %~1
exit /b 2
:parsed

set "DEST=%PREFIX%\bin"

if not exist "%DEST%\git-nest-main.sh" (
    echo git-nest-uninstall.bat: no git-nest installation found at %DEST%
    exit /b 1
)

echo Removing git-nest from %PREFIX%

rem Remove staged content (man pages, docs, skill) if present.
if exist "%PREFIX%\share" rmdir /s /q "%PREFIX%\share"

rem Unregister from Windows Apps & Features (Settings -> Apps) if the
rem installer registered the app there.
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\git-nest" /f >nul 2>&1

rem --- PATH removal (default: user, matching git-nest-install.bat's --add-path user) ---
if /i "%REMOVE_PATH%"=="current" (
    rem Strip DEST; from the current session PATH.
    set "NEWPATH="
    for %%P in ("%PATH:;=" "%") do (
        if /i not "%%~P"=="%DEST%" set "NEWPATH=!NEWPATH!;%%~P"
    )
    if defined NEWPATH set "NEWPATH=!NEWPATH:~1!"
    set "PATH=!NEWPATH!"
    echo   removed %DEST% from the PATH of this shell session
    goto cleanup_done
)

if /i "%REMOVE_PATH%"=="system" (
    rem Strip DEST; from the system PATH (HKLM). Requires elevation.
    powershell -NoProfile -Command "$d='%DEST%'; $p=[Environment]::GetEnvironmentVariable('Path','Machine'); $n=($p -split ';' | Where-Object { $_ -and $_ -ne $d }) -join ';'; if ($n -ne $p) { [Environment]::SetEnvironmentVariable('Path',$n,'Machine'); Write-Output 'removed from system PATH' } else { Write-Output 'not on system PATH' }"
    goto cleanup_done
)

rem Default: user PATH (HKCU).
powershell -NoProfile -Command "$d='%DEST%'; $p=[Environment]::GetEnvironmentVariable('Path','User'); $n=($p -split ';' | Where-Object { $_ -and $_ -ne $d }) -join ';'; if ($n -ne $p) { [Environment]::SetEnvironmentVariable('Path',$n,'User'); Write-Output 'removed from user PATH' } else { Write-Output 'not on user PATH' }"

:cleanup_done
rem Detached cleanup: the running script may live inside DEST, so the
rem payload is removed by a background cmd shortly after this script
rem exits (cmd.exe cannot delete a running batch file). ping provides the
rem delay because timeout refuses redirected stdin.
start "" /b cmd /c "ping -n 2 127.0.0.1 >nul & rmdir /s /q ""%DEST%"" & rd ""%PREFIX%"" >nul 2>&1"
echo git-nest uninstalled from %PREFIX%
exit /b 0

:help
echo git-nest uninstaller for Windows
echo.
echo   git-nest-uninstall.bat [--prefix DIR] [--remove-path user^|current^|system]
echo.
echo   --prefix DIR         Remove the installation under DIR (default: the
echo                        installation this script lives in, or
echo                        %%LOCALAPPDATA%%\Programs\git-nest from a checkout)
echo   --remove-path user   Remove DIR\bin from the user PATH (default)
echo   --remove-path current  Remove DIR\bin from the current shell session
echo   --remove-path system   Remove DIR\bin from the system PATH (elevated)
exit /b 0
