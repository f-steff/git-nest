@echo off
rem ===========================================================================
rem git-nest installer for Windows (cmd.exe)
rem
rem Installs the bin/ payload into a user-local directory and optionally adds
rem it to the PATH.
rem
rem Usage:
rem   git-nest-install.bat [--prefix DIR] [--from PATH] [--no-add-path]
rem
rem   --prefix DIR   Install under DIR (default: %LOCALAPPDATA%\Programs\git-nest).
rem                  The bin/ payload is installed to DIR\bin and that is the
rem                  only directory that needs to be on PATH.
rem   --from PATH    Source: a release zip or a directory containing bin\
rem                  (default: the checkout this script lives in).
rem   --no-add-path  Do NOT touch PATH. Default is --add-path user.
rem   --add-path     Add DIR\bin to PATH (the default):
rem                    user    - permanently for this user (setx, HKCU; default)
rem                    current - only in this shell session (no persistence)
rem                    system  - system-wide (HKLM; requires an elevated
rem                              prompt; machine-wide install under ProgramFiles)
rem
rem The default install path needs no administrator rights, following the
rem per-user convention used by VS Code and Git for Windows
rem (%LOCALAPPDATA%\Programs\). A machine-wide install would go under
rem %ProgramFiles% and require an elevated prompt.
rem ===========================================================================

setlocal enabledelayedexpansion

rem Capture the script location BEFORE any shift so %~dp0 stays valid.
set "SCRIPT_DIR=%~dp0"

set "PREFIX=%LOCALAPPDATA%\Programs\git-nest"
set "FROM="
set "ADD_PATH=user"

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--prefix" (
    set "PREFIX=%~2"
    shift
    shift
    goto parse
)
if /i "%~1"=="--from" (
    set "FROM=%~2"
    shift
    shift
    goto parse
)
if /i "%~1"=="--no-add-path" (
    set "ADD_PATH=off"
    shift
    goto parse
)
if /i "%~1"=="--add-path" (
    if /i "%~2"=="user" (
        set "ADD_PATH=user"
        shift
        shift
        goto parse
    )
    if /i "%~2"=="current" (
        set "ADD_PATH=current"
        shift
        shift
        goto parse
    )
    if /i "%~2"=="system" (
        set "ADD_PATH=system"
        shift
        shift
        goto parse
    )
    rem Bare --add-path with no mode: default to user.
    set "ADD_PATH=user"
    shift
    goto parse
)
if /i "%~1"=="--help" goto help
echo git-nest-install.bat: unknown argument: %~1
exit /b 2
:parsed

if "%FROM%"=="" set "FROM=%SCRIPT_DIR%.."

echo Installing git-nest to %PREFIX%

set "WORK=%TEMP%\gitnest-install"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%\payload" 2>nul

rem Resolve the payload: a directory containing bin\, a release zip of the
rem full staging tree (bin\ at the top), or a legacy zip whose top level is
rem the contents of bin\.
if exist "%FROM%\bin" (
    xcopy /e /i /q /y "%FROM%\bin\*" "%WORK%\payload\" >nul
    if exist "%FROM%\share" (
        xcopy /e /i /q /y "%FROM%\share\*" "%WORK%\staged-share\" >nul
    )
) else (
    powershell -NoProfile -Command "Expand-Archive -Force -Path '%FROM%' -DestinationPath '%WORK%\expanded'"
    if exist "%WORK%\expanded\bin" (
        rem Full staging tree: bin\ and share\ at the top.
        xcopy /e /i /q /y "%WORK%\expanded\bin\*" "%WORK%\payload\" >nul
        if exist "%WORK%\expanded\share" (
            xcopy /e /i /q /y "%WORK%\expanded\share\*" "%WORK%\staged-share\" >nul
        )
    ) else (
        rem Legacy payload zip: contents of bin\ at the top.
        xcopy /e /i /q /y "%WORK%\expanded\*" "%WORK%\payload\" >nul
    )
)
if not exist "%WORK%\payload\git-nest" (
    echo git-nest-install.bat: source does not contain bin\git-nest
    exit /b 1
)

rem Read the version from the payload (single source of truth).
set "VERSION=unknown"
for /f "tokens=1,* delims==" %%A in ('findstr /b "GIT_NEST_VERSION=" "%WORK%\payload\git-nest-main.sh"') do set "VERSION=%%B"

set "DEST=%PREFIX%\bin"
if exist "%DEST%" rmdir /s /q "%DEST%"
mkdir "%DEST%" 2>nul

rem Windows-relevant payload: the .bat/.ps1 launchers forward straight to
rem git-nest-main.sh (which self-dispatches), so only those three files plus
rem lib/ and the Windows install/uninstall scripts are needed.
copy /y "%WORK%\payload\git-nest.bat" "%DEST%\" >nul
copy /y "%WORK%\payload\git-nest.ps1" "%DEST%\" >nul
copy /y "%WORK%\payload\git-nest-main.sh" "%DEST%\" >nul
if exist "%WORK%\payload\git-nest-install.bat" copy /y "%WORK%\payload\git-nest-install.bat" "%DEST%\" >nul
if exist "%WORK%\payload\git-nest-uninstall.bat" copy /y "%WORK%\payload\git-nest-uninstall.bat" "%DEST%\" >nul
if exist "%WORK%\payload\lib" (
    xcopy /e /i /q /y "%WORK%\payload\lib\*" "%DEST%\lib\" >nul
)

rem Windows-relevant docs: md + html only (no man pages).
if exist "%WORK%\staged-share" (
    if exist "%PREFIX%\share" rmdir /s /q "%PREFIX%\share"
    if exist "%WORK%\staged-share\doc\git-nest" (
        mkdir "%PREFIX%\share\doc\git-nest" 2>nul
        for /d %%D in ("%WORK%\staged-share\doc\git-nest\*") do (
            if /i not "%%~nxD"=="guide" if /i not "%%~nxD"=="man" (
                xcopy /e /i /q /y "%%D\*" "%PREFIX%\share\doc\git-nest\%%~nxD\" >nul
            )
        )
        for %%F in ("%WORK%\staged-share\doc\git-nest\*.*") do (
            copy /y "%%F" "%PREFIX%\share\doc\git-nest\" >nul
        )
    )
    if exist "%WORK%\staged-share\git-nest\skill" (
        mkdir "%PREFIX%\share\git-nest\skill" 2>nul
        xcopy /e /i /q /y "%WORK%\staged-share\git-nest\skill\*" "%PREFIX%\share\git-nest\skill\" >nul
    )
)
rmdir /s /q "%WORK%"

echo Installed git-nest %VERSION%
echo   payload: %DEST%
if exist "%PREFIX%\share" echo   docs/man/skill: %PREFIX%\share

if "%ADD_PATH%"=="off" (
    echo Add to PATH: setx Path "!DEST!;%%PATH%%"
    echo "PATH was left untouched because --no-add-path was given"
    exit /b 0
)

rem --- PATH configuration ---
echo !PATH! | findstr /i /c:"!DEST!" >nul
if !errorlevel!==0 (
    echo   !DEST! is already on PATH
    exit /b 0
)

if /i "%ADD_PATH%"=="current" (
    set "PATH=!DEST!;!PATH!"
    echo   added !DEST! to the PATH of this shell session
    echo   "use --add-path user to make it permanent"
    exit /b 0
)

if /i "%ADD_PATH%"=="system" (
    rem System-wide PATH (HKLM). Requires an elevated prompt.
    powershell -NoProfile -Command "$d='%DEST%'; $p=[Environment]::GetEnvironmentVariable('Path','Machine'); if ($p -and ($p -split ';' -contains $d)) { Write-Output ('already on system PATH') } else { $n=if ($p) { $p.TrimEnd(';') + ';' + $d } else { $d }; [Environment]::SetEnvironmentVariable('Path',$n,'Machine'); Write-Output ('added ' + $d + ' to the system PATH - new processes will see it') }"
    exit /b 0
)

rem Default: user PATH (HKCU). Also registers the app in Windows
rem Apps & Features (Settings -> Apps) with a normal uninstall entry.
powershell -NoProfile -Command "& { $q=[char]34; $d='%DEST%'; $p=[Environment]::GetEnvironmentVariable('Path','User'); if ($p -and ($p -split ';' -contains $d)) { Write-Output ('already on the user PATH') } else { $n=if ($p) { $p.TrimEnd(';') + ';' + $d } else { $d }; [Environment]::SetEnvironmentVariable('Path',$n,'User'); Write-Output ('added ' + $d + ' to the user PATH - new shells will see it') }; $u='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\git-nest'; New-Item -Path $u -Force | Out-Null; New-ItemProperty -Path $u -Name DisplayName -Value 'git-nest' -PropertyType String -Force | Out-Null; New-ItemProperty -Path $u -Name DisplayVersion -Value '%VERSION%' -PropertyType String -Force | Out-Null; New-ItemProperty -Path $u -Name InstallLocation -Value '%PREFIX%' -PropertyType String -Force | Out-Null; New-ItemProperty -Path $u -Name UninstallString -Value ($q + '%DEST%\git-nest-uninstall.bat' + $q + ' --prefix ' + $q + '%PREFIX%' + $q) -PropertyType String -Force | Out-Null; Write-Output ('registered in Apps & Features') }"
exit /b 0

:help
echo git-nest installer for Windows
echo.
echo   git-nest-install.bat [--prefix DIR] [--from PATH] [--no-add-path]
echo.
echo   --prefix DIR        Install under DIR (default: %%LOCALAPPDATA%%\Programs\git-nest)
echo   --from PATH         Source: a release zip or a directory containing bin\
echo   --no-add-path       Do not touch PATH (print the instructions instead)
echo   --add-path user     Add DIR\bin to the user PATH permanently (setx; the default)
echo   --add-path current  Add DIR\bin to the current shell session only
echo   --add-path system   Add DIR\bin to the system PATH (elevated prompt required)
echo.
echo To remove the installation, run bin\git-nest-uninstall.bat with the same --prefix.
exit /b 0
