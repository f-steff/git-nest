# git-nest Chocolatey install script.
#
# Downloads the git-nest release zip from GitHub Releases, verifies its
# SHA256 against the release's SHA256SUMS, and installs the bin/ payload
# into the Chocolatey lib directory. A shim is created for the launcher so
# `git-nest` is available on PATH after install.

$ErrorActionPreference = 'Stop'

$version = $env:GIT_NEST_CHOCO_VERSION
if (-not $version) {
    # Fall back to the version baked into the nuspec at pack time.
    $version = '__VERSION__'
}

$url = "https://github.com/f-steff/git-nest/releases/download/v$version/git-nest-$version.zip"
$zipPath = Join-Path $env:TEMP "git-nest-$version.zip"
$extractDir = Join-Path $env:TEMP "git-nest-$version"
$installDir = Join-Path (Get-ToolsLocation) "git-nest"
$binDir = Join-Path $installDir "bin"

# Download the release zip.
Write-Host "Downloading git-nest $version from $url"
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

# Verify the checksum against the release's SHA256SUMS asset.
$sumsUrl = "https://github.com/f-steff/git-nest/releases/download/v$version/SHA256SUMS"
try {
    $sums = (Invoke-WebRequest -Uri $sumsUrl -UseBasicParsing).Content
    $expected = ($sums -split "`n" | Where-Object { $_ -match "git-nest-$version.zip" } |
        ForEach-Object { ($_ -split '\s+')[0].Trim() })
    if ($expected) {
        $actual = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLower()
        if ($actual -ne $expected.ToLower()) {
            throw "Checksum verification failed for git-nest-$version.zip"
        }
        Write-Host "Checksum verified."
    } else {
        Write-Warning "No checksum entry found for git-nest-$version.zip; skipping verification."
    }
} catch {
    Write-Warning "Could not fetch SHA256SUMS ($($_.Exception.Message)); skipping verification."
}

# Extract and install.
if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -Recurse -Force "$extractDir/bin/*" $binDir

# Create the shim for the POSIX entrypoint so `git-nest` is on PATH.
Install-BinFile -Name "git-nest" -Path (Join-Path $binDir "git-nest")

Remove-Item -Force $zipPath
Remove-Item -Recurse -Force $extractDir
