# Asks Steam what the newest public builds of the Wreckfest 2 dedicated server and of the game itself are, and writes the answer to
# latest-build.local.
# Read-only and anonymous: it uses SteamCMD's app-info query, which downloads nothing and needs no login. The settings page runs this
# in the background (see Start-WfLatestBuildCheck in network.ps1). It keeps the last good answer if a check fails.
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
$file = Get-WfLatestBuildFile $Root

function Save([string]$Error, $Parsed) {
    $old = Read-WfLatestBuildFile $Root
    $out = [ordered]@{
        latest            = if ($Parsed) { $Parsed.server.latest } else { [string]$old.latest }
        timeupdated       = if ($Parsed) { $Parsed.server.timeupdated } else { [string]$old.timeupdated }
        clientLatest      = if ($Parsed -and $Parsed.client) { $Parsed.client.latest } else { [string]$old.clientLatest }
        clientTimeupdated = if ($Parsed -and $Parsed.client) { $Parsed.client.timeupdated } else { [string]$old.clientTimeupdated }
        checked           = [DateTime]::UtcNow.ToString('o')
        error             = $Error
    }
    [IO.File]::WriteAllText($file, (ConvertTo-Json $out), (New-Object Text.UTF8Encoding $false))
}

$exe = Join-Path $SteamCmd 'steamcmd.exe'
if (-not (Test-Path $exe)) { Save 'SteamCMD is not installed yet.' $null; exit 1 }
if (Get-Process steamcmd -ErrorAction SilentlyContinue) { Save 'SteamCMD is busy (an install or update is running).' $null; exit 1 }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("wf2s-appinfo-" + [guid]::NewGuid().ToString('N') + '.txt')
try {
    $p = Start-Process $exe -ArgumentList @('+login', 'anonymous', '+app_info_update', '1', '+app_info_print', "$AppId", '+app_info_print', "$ClientAppId", '+quit') -WindowStyle Hidden -RedirectStandardOutput $tmp -PassThru
    if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Save 'Steam did not answer within 90 seconds.' $null; exit 1 }
    $text = if (Test-Path $tmp) { [IO.File]::ReadAllText($tmp) } else { '' }
    $server = ConvertFrom-WfAppInfo $text $AppId
    $client = ConvertFrom-WfAppInfo $text $ClientAppId   # may be $null; the server answer is the one that matters most
    if (-not $server) { Save 'Steam answered, but the build number could not be read from it.' $null; exit 1 }
    Save '' ([pscustomobject]@{ server = $server; client = $client })
    exit 0
} catch {
    Save $_.Exception.Message $null
    exit 1
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
