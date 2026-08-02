<#
.SYNOPSIS
    Record and restore reproducible nests of independent Git repositories.
.DESCRIPTION
    Cross-platform PowerShell launcher for git-nest.
    On Windows: locates Git Bash and forwards all arguments to the shell script.
    On Linux/macOS: runs the shell script via /bin/sh directly.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$shellScript = Join-Path $scriptDir "git-nest"

if ($IsWindows) {
    # Locate Git Bash from git.exe on PATH (same logic as bin/git-nest.bat).
    $gitExe = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitExe) {
        Write-Error "Git is not installed or not on PATH."
        exit 3
    }
    $bashExe = Join-Path (Split-Path -Parent $gitExe.Source | Split-Path -Parent) "bin\bash.exe"
    if (-not (Test-Path $bashExe)) {
        Write-Error "Git Bash not found at $bashExe"
        exit 3
    }
    if (-not (Test-Path $shellScript)) {
        # Fall back to PATH search.
        $shellScript = Get-Command git-nest -ErrorAction SilentlyContinue
        if (-not $shellScript) {
            Write-Error "git-nest not found next to this script or on PATH."
            exit 2
        }
        $shellScript = $shellScript.Source
    }
    & $bashExe --noprofile --norc $shellScript @args
    exit $LASTEXITCODE
} else {
    # Linux / macOS: run via /bin/sh directly.
    if (-not (Test-Path $shellScript)) {
        Write-Error "git-nest not found at $shellScript"
        exit 2
    }
    & /bin/sh $shellScript @args
    exit $LASTEXITCODE
}
