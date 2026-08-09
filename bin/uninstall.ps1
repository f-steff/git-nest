# git-nest uninstaller (PowerShell) -- remove a git-nest installation made
# by bin/install.ps1 and undo its PATH configuration. Works on Windows
# (PowerShell 5.1+), Linux, and macOS (pwsh).
#
#   Uninstall (defaults to the same prefix install.ps1 uses):
#     pwsh -File bin/uninstall.ps1
#
#   Custom prefix:
#     $env:GIT_NEST_PREFIX = "D:\tools\git-nest"
#     pwsh -File bin/uninstall.ps1
#
# The payload (DIR\bin), the staged content (DIR\share: man pages, docs,
# skill), the empty prefix directory, and the DIR\bin entry from the user
# PATH (the only PATH mode install.ps1 supports) are all removed.
#
# To remove the installation, run bin/uninstall.sh on POSIX shells or
# bin/uninstall.bat from cmd.exe.

$ErrorActionPreference = 'Stop'

$prefix = if ($env:GIT_NEST_PREFIX) { $env:GIT_NEST_PREFIX } else { Join-Path $HOME '.local' }
$dest = Join-Path $prefix 'bin'

if (-not (Test-Path -LiteralPath (Join-Path $dest 'git_nest.sh'))) {
    Write-Error "uninstall.ps1: no git-nest installation found at $dest"
    exit 1
}

Write-Output "Removing git-nest from $prefix"

# Remove the payload and staged content. Everything under DIR\bin and
# DIR\share belongs to git-nest.
Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
$share = Join-Path $prefix 'share'
if (Test-Path -LiteralPath $share) {
    Remove-Item -LiteralPath $share -Recurse -Force
}

# Remove the now-empty prefix if nothing remains.
if (Test-Path -LiteralPath $prefix) {
    $leftovers = Get-ChildItem -LiteralPath $prefix -Force -ErrorAction SilentlyContinue
    if (-not $leftovers) {
        Remove-Item -LiteralPath $prefix -Force
    }
}

# Remove the DIR\bin entry from the user PATH if present (install.ps1 adds
# it there with GIT_NEST_ADD_PATH=1).
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

Write-Output "git-nest uninstalled from $prefix"
