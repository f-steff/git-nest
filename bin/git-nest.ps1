<#
.SYNOPSIS
    Record and restore reproducible nests of independent Git repositories.
.DESCRIPTION
    Cross-platform PowerShell launcher for git-nest.
    On Windows: locates Git Bash and forwards all arguments to the shell script.
    On Linux/macOS: runs the shell script via /bin/sh directly.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$shellScript = Join-Path $scriptDir "git-nest-main.sh"

if ($IsWindows -or -not $IsLinux -and -not $IsMacOS) {
    # Locate Git Bash from git.exe on PATH (same intent as bin/git-nest.bat).
    # Walk up from the git.exe directory looking for a bin\bash.exe so any
    # Git for Windows layout works (cmd\, bin\, mingw64\bin\, ...).
    $gitExe = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitExe) {
        Write-Error "Git is not installed or not on PATH."
        exit 3
    }
    $bashExe = $null
    $dir = Split-Path -Parent $gitExe.Source
    while ($dir) {
        $candidate = Join-Path $dir "bin\bash.exe"
        if (Test-Path $candidate) { $bashExe = $candidate; break }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $bashExe) {
        Write-Error "Git Bash not found from git.exe at $($gitExe.Source)"
        exit 3
    }
    if (-not (Test-Path $shellScript)) {
        # Fall back to PATH search.
        $shellScript = Get-Command git-nest-main.sh -ErrorAction SilentlyContinue
        if (-not $shellScript) {
            Write-Error "git-nest-main.sh not found next to this script or on PATH."
            exit 2
        }
        $shellScript = $shellScript.Source
    }
    $env:GIT_NEST_WIN_LAUNCHER = 'powershell'
    & $bashExe --noprofile --norc $shellScript @args
    exit $LASTEXITCODE
} else {
    # Linux / macOS: run via /bin/sh directly.
    if (-not (Test-Path $shellScript)) {
        Write-Error "git-nest-main.sh not found at $shellScript"
        exit 2
    }
    & /bin/sh $shellScript @args
    exit $LASTEXITCODE
}
