# Replaces this app's own files with a newer release. Run by the settings page (from a temporary copy of this script, because it
# overwrites the scripts folder) or by hand:   .\scripts\self-update.ps1 -Root <app folder> -ZipPath <wf2s-vX.Y.Z.zip> -Version vX.Y.Z -NoRestart
#
# Safe by construction:
#  - nothing is touched until the zip is downloaded, matches GitHub's SHA-256 (when GitHub gave one), has the expected files and no
#    path that escapes the app folder, and is fully unpacked into a temporary folder;
#  - only the app's own files are replaced: scripts, ui, defaults, docs and the top-level files. instances\ (your server), server\ (the
#    game), steamcmd\, every *.local file (password, Steam name, caches) and .git are never touched or deleted;
#  - the old app files are copied to .update-backup first and put back if the swap fails.
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Url = '',
    [string]$ZipPath = '',         # use this zip instead of downloading (tests, offline)
    [string]$Version = '',
    [string]$Digest = '',          # 'sha256:<hex>' from GitHub
    [int]$UiPid = 0,               # the settings page to stop before the swap and replace afterwards
    [string]$Instance = 'main',
    [int]$Port = 30180,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$statusFile = Join-Path $Root 'app-update-status.local'
$AppDirs  = @('scripts', 'ui', 'defaults', 'docs')                                   # owned by the app: mirrored (stale files removed)
$SkipTop  = @('instances', 'server', 'steamcmd', 'dist', '.git', '.update-backup')   # never touched

function Status([string]$State, [string]$Message) {
    try { [IO.File]::WriteAllText($statusFile, (ConvertTo-Json @{ state = $State; message = $Message; version = $Version; at = [DateTime]::UtcNow.ToString('o') }), (New-Object Text.UTF8Encoding $false)) } catch { }
}
function Skip([string]$Rel) {
    $top = ($Rel -split '[\\/]')[0]
    ($SkipTop -contains $top) -or ($Rel -like '*.local')
}
function StartPage {
    if ($NoRestart) { return }
    Start-Process powershell.exe -WorkingDirectory $Root -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $Root 'scripts\ui.ps1') + '"'), '-Instance', $Instance, '-Port', "$Port") | Out-Null
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('wf2s-update-' + [guid]::NewGuid().ToString('N'))
$pageStopped = $false
$swapStarted = $false
$bak = Join-Path $Root '.update-backup'
try {
    New-Item -ItemType Directory -Force $work | Out-Null
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

    # 1. Get the zip
    $zip = $ZipPath
    if (-not $zip) {
        if (-not $Url.StartsWith('https://github.com/gerp93/wf2s/releases/download/')) { throw 'Refusing to download from an address that is not a release file of this project.' }
        Status 'running' 'Downloading the new version...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $zip = Join-Path $work 'app.zip'
        Invoke-WebRequest $Url -OutFile $zip -UseBasicParsing -TimeoutSec 300
    }
    if (-not (Test-Path $zip)) { throw "Zip not found: $zip" }

    # 2. Check it
    Status 'running' 'Checking the download...'
    if ($Digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $got = (Get-FileHash $zip -Algorithm SHA256).Hash
        if ($got -ne $Matches[1].ToUpper()) { throw 'The download does not match the checksum GitHub published for it. Nothing was changed.' }
    }
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $names = @($z.Entries | ForEach-Object { $_.FullName })
        foreach ($n in $names) {
            if ($n -notlike 'wf2s/*' -or $n -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($n) -or $n -match ':') { throw "The zip contains an unexpected path ($n). Nothing was changed." }
        }
        foreach ($need in 'wf2s/Start.cmd', 'wf2s/VERSION', 'wf2s/scripts/setup.ps1', 'wf2s/scripts/ui.ps1', 'wf2s/scripts/self-update.ps1', 'wf2s/ui/index.html') {
            if ($names -notcontains $need) { throw "The zip is not a complete release (missing $need). Nothing was changed." }
        }
        $leak = @($names | Where-Object { $_ -match '^wf2s/(instances|server|steamcmd)/' -or $_ -match '\.local$' })
        if ($leak.Count) { throw "The zip contains files that must not be in a release ($($leak[0])). Nothing was changed." }
    } finally { $z.Dispose() }
    $stage = Join-Path $work 'stage'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage)
    $new = Join-Path $stage 'wf2s'
    $newVersion = ([IO.File]::ReadAllText((Join-Path $new 'VERSION'))).Trim()
    if ($Version -and $newVersion -ne $Version) { throw "The zip is version $newVersion, not $Version. Nothing was changed." }

    # 3. Stop the settings page that is serving the update (the game server is a different process and keeps running)
    Status 'running' 'Installing...'
    if ($UiPid -gt 0 -and -not $NoRestart) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$UiPid" -ErrorAction SilentlyContinue
        if ($p -and $p.CommandLine -match 'ui\.ps1') { Stop-Process -Id $UiPid -Force -ErrorAction SilentlyContinue; $pageStopped = $true; Start-Sleep -Milliseconds 800 }
    }

    # 4. Back up the current app files, then swap
    if (Test-Path $bak) { Remove-Item $bak -Recurse -Force }
    New-Item -ItemType Directory -Force $bak | Out-Null
    foreach ($item in Get-ChildItem $Root -Force) {
        if (Skip $item.Name) { continue }
        if ($item.PSIsContainer -and $AppDirs -notcontains $item.Name) { continue }
        Copy-Item $item.FullName (Join-Path $bak $item.Name) -Recurse -Force
    }
    $swapStarted = $true
    $newRel = @{}
    foreach ($f in Get-ChildItem $new -Recurse -File -Force) {
        $rel = $f.FullName.Substring($new.Length).TrimStart('\')
        if (Skip $rel) { continue }
        $newRel[$rel.ToLower()] = $true
        $dest = Join-Path $Root $rel
        New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
        Copy-Item $f.FullName $dest -Force
    }
    foreach ($d in $AppDirs) {   # files the new version no longer has
        $dir = Join-Path $Root $d
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in Get-ChildItem $dir -Recurse -File -Force) {
            $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
            if (-not $newRel.ContainsKey($rel.ToLower()) -and -not (Skip $rel)) { Remove-Item $f.FullName -Force }
        }
    }
    Status 'done' "Updated to $newVersion."
    StartPage
} catch {
    $msg = $_.Exception.Message
    if ($swapStarted -and (Test-Path $bak)) {
        try {
            foreach ($item in Get-ChildItem $bak -Force) { Copy-Item $item.FullName (Join-Path $Root $item.Name) -Recurse -Force }
            $msg += ' The previous version was put back.'
        } catch { $msg += " Putting the previous version back failed too ($($_.Exception.Message)); the old files are in .update-backup." }
    }
    Status 'error' $msg
    if ($pageStopped) { StartPage }   # never leave the page dead
    Write-Warning $msg
    exit 1
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit 0
