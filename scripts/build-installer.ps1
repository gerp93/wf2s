# Builds the Windows installer, dist\wf2s-setup-<version>.exe, from the release zip that package.ps1 made (so the installer holds
# exactly the verified zip contents, with the same VERSION stamp). Needs Inno Setup 6 (ISCC.exe): `choco install innosetup`.
# Usage: .\scripts\build-installer.ps1 -Version v1.2.3 -ZipPath dist\wf2s-v1.2.3.zip [-OutDir dist]
param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$ZipPath, [string]$OutDir = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
if (-not $OutDir) { $OutDir = Join-Path $Root 'dist' }
$ZipPath = [IO.Path]::GetFullPath($ZipPath)
if (-not (Test-Path $ZipPath)) { throw "Zip not found: $ZipPath" }
$ver = $Version.TrimStart('v')
if ($ver -notmatch '^\d+\.\d+\.\d+$') { throw "Version '$Version' is not X.Y.Z." }

$iscc = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source,
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 (ISCC.exe) was not found. Install it (choco install innosetup) and try again.' }

$stage = Join-Path ([IO.Path]::GetTempPath()) ('wf2s-stage-' + [guid]::NewGuid().ToString('N'))
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $stage)
    $src = Join-Path $stage 'wf2s'
    if (-not (Test-Path (Join-Path $src 'Start.cmd'))) { throw 'The zip does not contain wf2s\Start.cmd.' }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    & $iscc "/DVersion=$ver" "/DSourceDir=$src" "/O$OutDir" (Join-Path $Root 'installer\wf2s.iss')
    if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)." }
    $exe = Join-Path $OutDir "wf2s-setup-v$ver.exe"
    if (-not (Test-Path $exe)) { throw "Expected $exe but it was not created." }
    Write-Host "Built $exe ($([math]::Round((Get-Item $exe).Length / 1KB)) KB)"
    $exe
} finally { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
