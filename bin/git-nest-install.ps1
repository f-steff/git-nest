# git-nest installer (PowerShell) -- install git-nest from a GitHub release
# or from a local checkout. Works on Windows (PowerShell 5.1+), Linux, and
# macOS (pwsh).
#
# Download mode (the recommended path) fetches the release archive;
# VERSION=latest (default) resolves the newest release via the GitHub API,
# VERSION=x.y.z downloads that release directly:
#
#   Latest release (cmd.exe / PowerShell):
#     powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex }"
#
#   Pinned version:
#     powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:VERSION='0.8.16'; iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex"
#
# The -ExecutionPolicy Bypass flag makes the one-liner work regardless of
# the machine's PowerShell execution policy.
#
# Options via environment variables (a piped one-liner cannot pass script
# arguments):
#   VERSION           release version, "latest" (default) or "x.y.z"
#   GIT_NEST_REPO     repository to download from (default: f-steff/git-nest)
#   GIT_NEST_PREFIX   install prefix (default: $HOME/.local)
#   GIT_NEST_ADD_PATH when set to '1', permanently append DIR/bin to the
#                     user PATH (default: only print the export line)
#
# When run as a file from a git-nest checkout (bin/git-nest-install.ps1), the
# script installs from that checkout instead of downloading.
#
# To remove the installation, run bin/git-nest-uninstall.ps1 with the same
# GIT_NEST_PREFIX.
#
# After install, add DIR/bin to PATH:
#   $env:PATH = "$HOME\.local\bin;$env:PATH"

$ErrorActionPreference = 'Stop'

function Write-InstallError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

# --- Resolve the install prefix -------------------------------------------
$prefix = if ($env:GIT_NEST_PREFIX) { $env:GIT_NEST_PREFIX } else { Join-Path $HOME '.local' }

# Platform flag: used for the download format and for the launcher set.
$isWinOs = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

# --- Source: checkout or download -----------------------------------------
$fromDir = $null
$download = $false

if ($PSScriptRoot) {
    # Run as a file: use the surrounding checkout when bin/git-nest-install.ps1 sits
    # next to bin/git-nest.
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'git-nest')) {
        $fromDir = Split-Path $PSScriptRoot -Parent
    }
}
if (-not $fromDir) {
    $download = $true
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('gitnest-install-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    if ($download) {
        $version = if ($env:VERSION) { $env:VERSION } else { 'latest' }
        $repo = if ($env:GIT_NEST_REPO) { $env:GIT_NEST_REPO } else { 'f-steff/git-nest' }

        if ($version -eq 'latest') {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
            if (-not $release.tag_name) {
                Write-InstallError "cannot resolve the latest release via the GitHub API"
            }
            $version = $release.tag_name.TrimStart('v')
        }

        # Windows expands the zip natively (Expand-Archive); POSIX shells
        # use tar. The download format therefore depends on the platform.
        $ext = if ($isWinOs) { 'zip' } else { 'tar.gz' }
        $url = "https://github.com/$repo/releases/download/v$version/git-nest-$version.$ext"
        Write-Output "Downloading $url"
        Invoke-WebRequest -UseBasicParsing -OutFile (Join-Path $work ("git-nest.$ext")) -Uri $url

        # Best-effort checksum verification against the release SHA256SUMS.
        $sumsUrl = "https://github.com/$repo/releases/download/v$version/SHA256SUMS"
        $sumsFile = Join-Path $work 'SHA256SUMS'
        try {
            Invoke-WebRequest -UseBasicParsing -OutFile $sumsFile -Uri $sumsUrl
            $archive = Join-Path $work ("git-nest.$ext")
            $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            $expected = (Get-Content $sumsFile | Where-Object { $_ -match "git-nest-$version\.$ext" } | ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1)
            if ($expected -and $expected.ToLowerInvariant() -ne $actual) {
                Write-InstallError "SHA256SUMS verification failed for git-nest-$version.$ext"
            }
            Write-Output "tarball checksum verified"
        } catch {
            # SHA256SUMS unavailable (e.g. very old release); continue.
        }

        $extract = Join-Path $work 'extract'
        New-Item -ItemType Directory -Path $extract | Out-Null
        if ($isWinOs) {
            Expand-Archive -LiteralPath (Join-Path $work 'git-nest.zip') -DestinationPath $extract
        } else {
            tar -xzf (Join-Path $work 'git-nest.tar.gz') -C $extract
        }
        $fromDir = $extract
    }

    $payload = Join-Path $fromDir 'bin'
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'git-nest'))) {
        Write-InstallError "source does not contain bin/git-nest"
    }

    $dest = Join-Path $prefix 'bin'
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    # Clear any previous install so stale files cannot linger. On Windows
    # the .bat/.ps1 launchers are kept; on POSIX only .bat is skipped (the
    # .ps1 launcher also runs under pwsh on Linux/macOS).
    Get-ChildItem -LiteralPath $dest -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Get-ChildItem -LiteralPath $payload | ForEach-Object {
        if (-not $isWinOs -and $_.Name -eq 'git-nest.bat') { return }
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
    }

    # Staged content for full release archives: man pages, docs, skill.
    $share = Join-Path $fromDir 'share'
    if (Test-Path -LiteralPath $share) {
        $destShare = Join-Path $prefix 'share'
        New-Item -ItemType Directory -Path $destShare -Force | Out-Null
        Get-ChildItem -LiteralPath $share | Copy-Item -Destination $destShare -Recurse -Force
    }

    $version = 'unknown'
    $versionFile = Join-Path $dest 'git_nest.sh'
    if (Test-Path -LiteralPath $versionFile) {
        $m = Select-String -LiteralPath $versionFile -Pattern '^GIT_NEST_VERSION='
        if ($m) { $version = ($m.Line -replace '^GIT_NEST_VERSION=', '').Trim() }
    }

    Write-Output "Installed git-nest $version"
    Write-Output "  payload: $dest"

    if ($env:GIT_NEST_ADD_PATH -eq '1') {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$dest*") {
            $newPath = if ($userPath) { $dest + ';' + $userPath } else { $dest }
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-Output "  added $dest to the user PATH"
        } else {
            Write-Output "  PATH already contains $dest"
        }
        # Register the app in Windows Apps & Features (Settings -> Apps)
        # with a normal uninstall entry pointing at the co-located
        # uninstaller.
        $un = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\git-nest"
        New-Item -Path $un -Force | Out-Null
        New-ItemProperty -Path $un -Name DisplayName -Value 'git-nest' -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $un -Name DisplayVersion -Value $version -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $un -Name InstallLocation -Value $prefix -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $un -Name UninstallString -Value ('"' + (Join-Path $dest 'git-nest-uninstall.bat') + '" --prefix "' + $prefix + '"') -PropertyType String -Force | Out-Null
        Write-Output "  registered in Apps & Features"
    } else {
        Write-Output "Add to PATH: `$env:PATH = `"$dest;`$env:PATH`""
        Write-Output "(re-run with the environment variable GIT_NEST_ADD_PATH=1 to configure it permanently)"
        Write-Output "(to remove the installation, run bin/git-nest-uninstall.ps1)"
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
