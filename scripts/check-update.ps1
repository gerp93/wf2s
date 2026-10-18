# Asks the internet what is newest, and writes the answer to latest-build.local. Two read-only, anonymous questions:
#   1. Steam (SteamCMD's app-info query): the newest public build of the Wreckfest 2 dedicated server and of the game itself.
#      Downloads nothing, needs no login.
#   2. GitHub: the newest release of THIS app (api.github.com, no token).
# The settings page runs this in the background (see Start-WfLatestBuildCheck in network.ps1). Each answer is kept from the last
# successful check if its question fails this time, and the error is recorded.
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
$file = Get-WfLatestBuildFile $Root
$old = Read-WfLatestBuildFile $Root
$r = [ordered]@{
    latest            = [string]$old.latest
    timeupdated       = [string]$old.timeupdated
    clientLatest      = [string]$old.clientLatest
    clientTimeupdated = [string]$old.clientTimeupdated
    appLatest         = [string]$old.appLatest
    appUrl            = [string]$old.appUrl
    appDigest         = [string]$old.appDigest
    appPublished      = [string]$old.appPublished
    checked           = ''
    error             = ''
}
$errors = @()

# ---- 1. Steam ----
$exe = Join-Path $SteamCmd 'steamcmd.exe'
if (-not (Test-Path $exe)) { $errors += 'Steam: SteamCMD is not installed yet.' }
elseif (Get-Process steamcmd -ErrorAction SilentlyContinue) { $errors += 'Steam: SteamCMD is busy (an install or update is running).' }
else {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("wf2s-appinfo-" + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process $exe -ArgumentList @('+login', 'anonymous', '+app_info_update', '1', '+app_info_print', "$AppId", '+app_info_print', "$ClientAppId", '+quit') -WindowStyle Hidden -RedirectStandardOutput $tmp -PassThru
        if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $errors += 'Steam did not answer within 90 seconds.' }
        else {
            $text = if (Test-Path $tmp) { [IO.File]::ReadAllText($tmp) } else { '' }
            $server = ConvertFrom-WfAppInfo $text $AppId
            $client = ConvertFrom-WfAppInfo $text $ClientAppId   # may be $null; the server answer matters most
            if (-not $server) { $errors += 'Steam answered, but the build number could not be read from it.' }
            else {
                $r.latest = $server.latest; $r.timeupdated = $server.timeupdated
                if ($client) { $r.clientLatest = $client.latest; $r.clientTimeupdated = $client.timeupdated }
            }
        }
    } catch { $errors += "Steam: $($_.Exception.Message)" }
    finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

# ---- 2. This app's newest release on GitHub ----
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod "https://api.github.com/repos/$($script:WfAppRepo)/releases/latest" -Headers @{ 'User-Agent' = 'wf2s'; Accept = 'application/vnd.github+json' } -TimeoutSec 20
    $info = ConvertFrom-WfRelease $rel
    if ($info) { $r.appLatest = $info.tag; $r.appUrl = $info.url; $r.appDigest = $info.digest; $r.appPublished = $info.published }
    else { $errors += 'GitHub: the latest release has no app zip.' }
} catch {
    # A repo with no release yet answers 404; that is not worth an error line.
    if ($_.Exception.Message -notmatch '404') { $errors += "GitHub: $($_.Exception.Message)" }
}

$r.checked = [DateTime]::UtcNow.ToString('o')
$r.error = $errors -join ' '
[IO.File]::WriteAllText($file, (ConvertTo-Json $r), (New-Object Text.UTF8Encoding $false))
exit $(if ($errors.Count) { 1 } else { 0 })
