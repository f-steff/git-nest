# git-nest uninstaller (PowerShell) -- remove a git-nest installation and
# undo its PATH configuration. Works on Windows (PowerShell 5.1+), Linux,
# and macOS (pwsh).
#
# The uninstaller is copied into the installed bin\ directory, which is on
# PATH, so it is normally invoked directly:
#
#   git-nest-uninstall.ps1                  (removes this installation)
#   $env:GIT_NEST_PREFIX = "D:\tools\git-nest"
#   git-nest-uninstall.ps1                  (custom prefix)
#
# The payload (DIR\bin), the staged content (DIR\share: man pages, docs,
# skill), the empty prefix directory, the DIR\bin entry from the user
# PATH, and the Windows Apps & Features registration are all removed.
#
# To remove the installation, run bin/git-nest-uninstall.sh on POSIX
# shells or bin/git-nest-uninstall.bat from cmd.exe.

$ErrorActionPreference = 'Stop'

$isWinOs = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

# Resolve the prefix: explicit GIT_NEST_PREFIX wins; otherwise this
# script's own parent when it sits in an installed <prefix>\bin (and is
# not running from the source checkout); otherwise the installer default.
$prefix = $null
if ($env:GIT_NEST_PREFIX) {
    $prefix = $env:GIT_NEST_PREFIX
} elseif ($PSScriptRoot) {
    $parent = Split-Path $PSScriptRoot -Parent
    $inCheckout = (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'git-nest-main.sh')) -and `
        ((Test-Path -LiteralPath (Join-Path $parent '.git')) -or `
         (Test-Path -LiteralPath (Join-Path $parent 'AGENTS.md')))
    if (-not $inCheckout) {
        $prefix = $parent
    }
}
if (-not $prefix) {
    $prefix = Join-Path $HOME '.local'
}

$dest = Join-Path $prefix 'bin'

if (-not (Test-Path -LiteralPath (Join-Path $dest 'git-nest-main.sh'))) {
    Write-Error "uninstall.ps1: no git-nest installation found at $dest"
    exit 1
}

Write-Output "Removing git-nest from $prefix"

# Remove staged content (man pages, docs, skill) if present.
$share = Join-Path $prefix 'share'
if (Test-Path -LiteralPath $share) {
    Remove-Item -LiteralPath $share -Recurse -Force
}

# Unregister from Windows Apps & Features (Settings -> Apps) if the
# installer registered the app there.
if ($isWinOs) {
    $un = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\git-nest'
    if (Test-Path -LiteralPath $un) {
        Remove-Item -LiteralPath $un -Force
        Write-Output "  removed the Apps & Features registration"
    }
}

# Remove the DIR\bin entry from the user PATH if present (install.ps1 adds
# it there with GIT_NEST_ADD_PATH=1).
if ($isWinOs) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath) {
        $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $dest }
        $newPath = $parts -join ';'
        if ($newPath -ne $userPath) {
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-Output "  removed $dest from the user PATH"
        } else {
            Write-Output "  $dest was not on the user PATH"
        }
    }
}

Write-Output "git-nest uninstalled from $prefix"

# Remove the payload and the now-empty prefix. This may delete the
# running script and its directory; PowerShell reads the script fully
# before executing, so this is safe (unlike cmd.exe).
Remove-Item -LiteralPath $dest -Recurse -Force
$leftovers = Get-ChildItem -LiteralPath $prefix -Force -ErrorAction SilentlyContinue
if (-not $leftovers) {
    Remove-Item -LiteralPath $prefix -Force -ErrorAction SilentlyContinue
}
