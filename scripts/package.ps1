# Builds the release zip: dist\wf2s-<version>.zip, containing only files tracked in git (so nothing from your own server,
# the game or SteamCMD can end up in it), under one top-level folder. Then checks the zip for anything that must never ship.
# Usage: .\scripts\package.ps1 [-Version v0.1.0] [-OutDir dist]
param([string]$Version = '', [string]$OutDir = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
Push-Location $Root
try {
    if (-not $Version) { $Version = (& git describe --tags --always 2>$null); if (-not $Version) { $Version = 'dev' } }
    $Version = $Version.Trim() -replace '[^A-Za-z0-9._-]', '-'
    if (-not $OutDir) { $OutDir = Join-Path $Root 'dist' }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $zipPath = Join-Path $OutDir "wf2s-$Version.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath }

    $files = @(& git ls-files) | Where-Object { $_ -and $_ -notmatch '^\.github/' -and $_ -ne '.gitignore' -and $_ -ne '.gitattributes' -and $_ -ne 'VERSION_BUMP.md' }
    if (-not $files) { throw 'git ls-files returned nothing. Run this inside the git checkout.' }

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        foreach ($f in $files) {
            if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) { continue }   # tracked but deleted in the working tree
            $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $Root $f), "wf2s/$f", 'Optimal')
        }
    } finally { $zip.Dispose() }

    # Never ship: the game, SteamCMD, anyone's server folder, secrets.
    $bad = @()
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        $bad = @($names | Where-Object { $_ -match '^wf2s/(server|steamcmd|instances|dist|\.personal-backup)/' -or $_ -match '\.local$' -or $_ -match '(^|/)(password|admins)\.' -or $_ -match '\.(exe|dll|rpck)$' })
        foreach ($need in 'wf2s/Start.cmd', 'wf2s/LICENSE', 'wf2s/README.md', 'wf2s/scripts/setup.ps1', 'wf2s/ui/index.html', 'wf2s/defaults/instance/server_config.template.scnf') {
            if ($names -notcontains $need) { throw "The zip is missing $need." }
        }
        Write-Host "$($names.Count) files in $zipPath"
    } finally { $zip.Dispose() }
    if ($bad.Count) { Remove-Item $zipPath; throw ("The zip would contain files that must not ship:`n  " + ($bad -join "`n  ")) }
    $zipPath
} finally { Pop-Location }
