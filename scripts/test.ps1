# Automated checks that need no game and no Steam account (CI runs this on every push). Run: .\scripts\test.ps1
# It creates a throwaway instance named ci-test inside instances\ and removes it again. It never touches another instance.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
$script:fail = 0
function Check([string]$what, [scriptblock]$test) {
    try { if (& $test) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what" -ForegroundColor Red; $script:fail++ } }
    catch { Write-Host "  FAIL  $what : $($_.Exception.Message)" -ForegroundColor Red; $script:fail++ }
}
$name = 'ci-test'
$dir  = Join-Path $Root "instances\$name"
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }

try {
    Write-Host 'Scripts parse'
    foreach ($f in Get-ChildItem $PSScriptRoot -Filter *.ps1) {
        Check $f.Name { $e = $null; $null = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e); -not $e }
    }

    Write-Host 'Default files are valid'
    foreach ($f in Get-ChildItem (Join-Path $Root 'defaults') -Recurse -File | Where-Object { $_.Extension -in '.scnf', '.becl', '.ccnl', '.sprv', '.json' }) {
        Check $f.Name { $null = Read-WfJson $f.FullName; $true }
    }
    $defLoop = Join-Path $Root 'defaults\instance\default_loop.template.becl'
    Check 'default rotation has events' { @((Read-WfJson $defLoop).events).Count -ge 40 }
    Check 'default rotation has events switched on' { @(Get-WfEnabledEvents (Read-WfJson $defLoop)).Count -ge 30 }
    Check 'default server name is neutral' { (Read-WfJson (Join-Path $Root 'defaults\instance\server_config.template.scnf')).'net server config'[0].name -eq 'My Wreckfest 2 Server' }

    Write-Host 'Creating an instance'
    Check 'new instance is created' { Initialize-WfInstance $Root $name }
    foreach ($f in 'server_config.template.scnf', 'default_loop.template.becl', 'server_cup_config.template.ccnl', 'server_privilege.template.sprv') {
        Check "has $f" { Test-Path (Join-Path $dir $f) }
    }
    Check 'six shipped cups' { @((Read-WfCups $dir).cups).Count -eq 6 }
    $cfgFile = Join-Path $dir 'server_config.template.scnf'
    [IO.File]::WriteAllText($cfgFile, ([IO.File]::ReadAllText($cfgFile)).Replace('My Wreckfest 2 Server', 'Edited'))
    Check 're-running never overwrites an existing instance' { (-not (Initialize-WfInstance $Root $name)) -and (([IO.File]::ReadAllText($cfgFile)) -match 'Edited') }
    Check 'rejects a bad instance name' { try { $null = Get-WfInstanceDir $Root '..\x'; $false } catch { $true } }

    Write-Host 'Setup (no prompts, no download, no firewall)'
    $pw = ConvertTo-SecureString 'ci-test-password' -AsPlainText -Force
    Remove-Item $dir -Recurse -Force
    & "$PSScriptRoot\setup.ps1" -Instance $name -SkipInstall -SkipFirewall -NoPrompt -ServerName 'CI Server' -Password $pw -AdminSteamId 'https://steamcommunity.com/profiles/76561198000000001' *>&1 | Out-Null
    Check 'setup exit code 0' { $LASTEXITCODE -eq 0 }
    Check 'password saved' { (Get-WfPassword $dir) -eq 'ci-test-password' }
    Check 'admin saved' { (Get-Content (Join-Path $dir 'admins.local') -Raw).Trim() -eq '76561198000000001' }
    Check 'server name saved as a Global default' { (Read-WfOverrides $dir)['name'] -eq 'CI Server' }
    Check 'password history says setup.ps1' { @(Read-WfPasswordHistory $dir)[0].by -eq 'setup.ps1' }
    Check 'instance problems list is only about the missing game' { $p = @(Get-WfInstanceProblems $Root $name); (Test-Path (Join-Path $Server 'Wreckfest2.exe')) -or ($p.Count -eq 1 -and $p[0] -match 'game server') }

    Write-Host 'Generators'
    Build-WfLoop $dir
    Check 'default_loop.becl generated' { @((Read-WfJson (Join-Path $dir 'default_loop.becl')).events).Count -ge 30 }
    Check 'generated loop has no page bookkeeping' { -not ((Get-Content (Join-Path $dir 'default_loop.becl') -Raw) -match '"overrides"|"disabled"') }
    $cfg = Read-WfJson $cfgFile; Set-WfServerOverrides $cfg (Read-WfOverrides $dir)
    Check 'server name override applied' { $cfg.'net server config'[0].name -eq 'CI Server' }
    Check 'cups round trip' { $c = Read-WfCups $dir; Save-WfCups $dir $c; @((Read-WfCups $dir).cups).Count -eq 6 }

    Write-Host 'Helpers'
    Check 'SteamID accepted'            { (ConvertTo-WfSteamId '76561198000000001') -eq '76561198000000001' }
    Check 'profile link accepted'       { (ConvertTo-WfSteamId 'https://steamcommunity.com/profiles/76561198000000001/') -eq '76561198000000001' }
    Check 'vanity link refused'         { $null -eq (ConvertTo-WfSteamId 'https://steamcommunity.com/id/someone') }
    Check 'junk refused'                { $null -eq (ConvertTo-WfSteamId '12345') }
    Check 'private addresses'           { (Test-WfPrivateAddress '192.168.1.5') -and (Test-WfPrivateAddress '100.64.3.2') -and (Test-WfPrivateAddress '10.0.0.1') -and (Test-WfPrivateAddress '172.20.1.1') }
    Check 'public addresses'            { (-not (Test-WfPrivateAddress '8.8.8.8')) -and (-not (Test-WfPrivateAddress '172.32.0.1')) -and (-not (Test-WfPrivateAddress '100.128.0.1')) }
    $rs = ConvertFrom-WfConsoleReachability @('Router port forwarding using UPnP unavailable. Use manual port forwarding if needed. [code: 5]', 'Server is unreachable.')
    Check 'console: unreachable + no UPnP'  { $rs.status -eq 'unreachable' -and $rs.upnp -eq $false }
    $rs = ConvertFrom-WfConsoleReachability @('Server is unreachable.', 'Router port forwarded using UPnP. External endpoint at 203.0.113.9:30100.', 'Server is reachable from public network.')
    Check 'console: reachable via UPnP (last verdict wins)' { $rs.status -eq 'reachable' -and $rs.upnp -eq $true -and $rs.endpoint -eq '203.0.113.9' -and -not $rs.privateEndpoint }
    $rs = ConvertFrom-WfConsoleReachability @('Router port forwarded using UPnP. External endpoint at 100.72.1.4:30100.')
    Check 'console: CGNAT address flagged' { $rs.privateEndpoint -and $rs.status -eq 'unknown' }
    $rs = ConvertFrom-WfConsoleReachability @('Router port forwarding using UPnP unavailable. Use manual port forwarding if needed. [code: 30]', 'Server is reachable from public network.', 'Server address set to: 203.0.113.9:30100', 'Server Started')
    Check 'console: advertised public address' { $rs.status -eq 'reachable' -and $rs.address -eq '203.0.113.9' -and -not $rs.privateEndpoint }
    $rs = ConvertFrom-WfConsoleReachability @('Server is unreachable.', 'Server address set to: 10.1.2.3:30100')
    Check 'console: advertised private address flagged' { $rs.privateEndpoint -and $rs.address -eq '10.1.2.3' }
    Check 'console: nothing printed yet' { (ConvertFrom-WfConsoleReachability @('> ', 'Server Started')).status -eq 'unknown' }
    Check 'game version from window title'  { (ConvertFrom-WfWindowTitle 'Wreckfest 2 | 0.377396') -eq '0.377396' -and (ConvertFrom-WfWindowTitle 'Command Prompt') -eq '' }
    Check 'known build names a game version' { (Get-WfKnownBuild $Root).gameVersion -match '^\d+\.\d+$' }
    $info = @'
AppID : 3519390, change number : 1/1, last change : Fri Oct 16 19:19:37 2026
"3519390"
{
	"depots"
	{
		"branches"
		{
			"public"
			{
				"buildid"		"111"
			}
		}
	}
}
AppID : 1203190, change number : 2/2, last change : Fri Oct 16 19:19:37 2026
"1203190"
{
	"depots"
	{
		"public"
		{
			"x"		"y"
		}
		"branches"
		{
			"public"
			{
				"buildid"		"222"
				"timeupdated"		"1792069253"
			}
		}
	}
}
'@
    Check 'Steam app info: server build'   { (ConvertFrom-WfAppInfo $info 3519390).latest -eq '111' }
    Check 'Steam app info: game build + time' { $c = ConvertFrom-WfAppInfo $info 1203190; $c.latest -eq '222' -and $c.timeupdated -like '2026-10-*' }
    Check 'Steam app info: unknown app or junk' { ($null -eq (ConvertFrom-WfAppInfo $info 999)) -and ($null -eq (ConvertFrom-WfAppInfo 'Login Failure' 3519390)) }
    Check 'Steam client lookup answers' { $s = Get-WfSteamClient; ($s.installed -is [bool]) -and ($s.gameInstalled -is [bool]) }
    Check 'latest-build state is well formed' { $l = Get-WfLatestBuild $Root $Server; ($l.updateAvailable -is [bool]) -and ($l.clientUpdateAvailable -is [bool]) -and ($l.checking -is [bool]) }
    Check 'game port read'              { (Get-WfGamePort $dir) -eq 30100 }
    Check 'known build file readable'   { (Get-WfKnownBuild $Root).buildid -match '^\d+$' }

    Write-Host 'App versions and self-update'
    Check 'newer version detected'   { (Test-WfNewerVersion 'v0.0.1' 'v0.0.2') -and (Test-WfNewerVersion 'v0.0.9' 'v0.0.10') -and (Test-WfNewerVersion 'v1.9.9' 'v2.0.0') }
    Check 'same, older and junk are not newer' { -not ((Test-WfNewerVersion 'v1.0.0' 'v1.0.0') -or (Test-WfNewerVersion 'v1.0.1' 'v1.0.0') -or (Test-WfNewerVersion 'dev' 'v1.0.0') -or (Test-WfNewerVersion '' 'v1.0.0') -or (Test-WfNewerVersion 'v1.0.0' 'latest')) }
    $rel = ConvertFrom-Json '{"tag_name":"v1.2.3","draft":false,"prerelease":false,"published_at":"2026-10-18T00:00:00Z","assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"},{"name":"wf2s-v1.2.3.zip","browser_download_url":"https://github.com/gerp93/wf2s/releases/download/v1.2.3/wf2s-v1.2.3.zip","digest":"sha256:abc"}]}'
    Check 'release parsed (tag, zip, digest)' { $i = ConvertFrom-WfRelease $rel; $i.tag -eq 'v1.2.3' -and $i.url -like '*wf2s-v1.2.3.zip' -and $i.digest -eq 'sha256:abc' }
    Check 'draft, pre-release and zip-less releases ignored' {
        $d = ConvertFrom-Json '{"tag_name":"v1.2.3","draft":true,"prerelease":false,"assets":[{"name":"wf2s-v1.2.3.zip","browser_download_url":"u"}]}'
        $p = ConvertFrom-Json '{"tag_name":"v1.2.3","draft":false,"prerelease":true,"assets":[{"name":"wf2s-v1.2.3.zip","browser_download_url":"u"}]}'
        $n = ConvertFrom-Json '{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[]}'
        ($null -eq (ConvertFrom-WfRelease $d)) -and ($null -eq (ConvertFrom-WfRelease $p)) -and ($null -eq (ConvertFrom-WfRelease $n)) }
    Check 'a git checkout refuses to self-update' { try { $null = Start-WfAppUpdate $Root 'x' 30180; $false } catch { $_.Exception.Message -match 'git' } }

    $selfWork = Join-Path ([IO.Path]::GetTempPath()) "wf2s-selftest-$([guid]::NewGuid().ToString('N'))"
    try {
        $zipDir = Join-Path $selfWork 'zip'
        $zip = & "$PSScriptRoot\package.ps1" -Version 'v9.9.9' -OutDir $zipDir | Select-Object -Last 1
        $fake = Join-Path $selfWork 'app'
        function PutFile([string]$rel, [string]$text) { $f = Join-Path $fake $rel; New-Item -ItemType Directory -Force (Split-Path $f -Parent) | Out-Null; [IO.File]::WriteAllText($f, $text) }
        function GetFile([string]$rel) { $f = Join-Path $fake $rel; if (Test-Path $f) { [IO.File]::ReadAllText($f) } else { $null } }
        PutFile 'VERSION' 'v0.0.1'; PutFile 'README.md' 'old readme'; PutFile 'scripts\setup.ps1' 'old setup'; PutFile 'scripts\old-only.ps1' 'stale'; PutFile 'ui\index.html' 'old page'
        PutFile 'instances\main\password.local' 'secret'; PutFile 'instances\main\settings.json' 'mine'; PutFile 'server\Wreckfest2.exe' 'game'; PutFile 'steamcmd\steamcmd.exe' 'steam'
        PutFile 'steam-user.local' 'someone'; PutFile 'latest-build.local' 'cache'

        # a bad zip changes nothing
        $bad = Join-Path $selfWork 'bad.zip'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zf = [IO.Compression.ZipFile]::Open($bad, 'Create'); $e = $zf.CreateEntry('wf2s/README.md'); $sw = New-Object IO.StreamWriter($e.Open()); $sw.Write('x'); $sw.Dispose(); $zf.Dispose()
        $null = & "$PSScriptRoot\self-update.ps1" -Root $fake -ZipPath $bad -NoRestart *>&1
        Check 'an incomplete zip is refused and nothing changes' { ($LASTEXITCODE -eq 1) -and (GetFile 'VERSION') -eq 'v0.0.1' -and (GetFile 'scripts\setup.ps1') -eq 'old setup' }
        $null = & "$PSScriptRoot\self-update.ps1" -Root $fake -ZipPath $zip -Digest ('sha256:' + ('0' * 64)) -NoRestart *>&1
        Check 'a wrong checksum is refused and nothing changes' { ($LASTEXITCODE -eq 1) -and (GetFile 'VERSION') -eq 'v0.0.1' }
        $null = & "$PSScriptRoot\self-update.ps1" -Root $fake -ZipPath $zip -Version 'v1.2.3' -NoRestart *>&1
        Check 'a zip of a different version is refused' { ($LASTEXITCODE -eq 1) -and (GetFile 'VERSION') -eq 'v0.0.1' }
        Check 'a refusal is recorded for the page' { (Read-WfJson (Join-Path $fake 'app-update-status.local')).state -eq 'error' }

        # the real thing
        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
        $null = & "$PSScriptRoot\self-update.ps1" -Root $fake -ZipPath $zip -Version 'v9.9.9' -Digest "sha256:$hash" -NoRestart *>&1
        Check 'update succeeds'                    { $LASTEXITCODE -eq 0 }
        Check 'version is stamped'                 { (GetFile 'VERSION') -eq 'v9.9.9' }
        Check 'app files are replaced'             { (GetFile 'scripts\setup.ps1') -ne 'old setup' -and (GetFile 'ui\index.html') -ne 'old page' -and (GetFile 'README.md') -ne 'old readme' }
        Check 'files the new version dropped are removed' { $null -eq (GetFile 'scripts\old-only.ps1') }
        Check 'your server folder is untouched'    { (GetFile 'instances\main\password.local') -eq 'secret' -and (GetFile 'instances\main\settings.json') -eq 'mine' }
        Check 'the game and SteamCMD are untouched' { (GetFile 'server\Wreckfest2.exe') -eq 'game' -and (GetFile 'steamcmd\steamcmd.exe') -eq 'steam' }
        Check '*.local files are untouched'        { (GetFile 'steam-user.local') -eq 'someone' -and (GetFile 'latest-build.local') -eq 'cache' }
        Check 'the old files are backed up'        { (GetFile '.update-backup\scripts\setup.ps1') -eq 'old setup' -and (GetFile '.update-backup\VERSION') -eq 'v0.0.1' }
        Check 'success is recorded for the page'   { (Read-WfJson (Join-Path $fake 'app-update-status.local')).state -eq 'done' }
        Check 'the zip carries its own version'    { $z = [IO.Compression.ZipFile]::OpenRead($zip); try { $en = $z.GetEntry('wf2s/VERSION'); $rd = New-Object IO.StreamReader($en.Open()); try { $rd.ReadToEnd() -eq 'v9.9.9' } finally { $rd.Dispose() } } finally { $z.Dispose() } }
    } finally { Remove-Item $selfWork -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host 'Settings page'
    $port = 30190 + (Get-Random -Maximum 9)
    $ui = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'ui.ps1') + '"'), '-Instance', $name, '-Port', $port)
    try {
        $state = $null
        for ($i = 0; $i -lt 30 -and -not $state; $i++) { Start-Sleep -Milliseconds 500; try { $state = Invoke-RestMethod "http://127.0.0.1:$port/api/state" } catch { } }
        Check 'page answers' { $state.instance -eq $name }
        Check 'state has build info' { $null -ne $state.build }
        Check 'password is not in the state' { -not ((ConvertTo-Json $state -Depth 6) -match 'ci-test-password') }
        Check 'state has Steam client info' { $null -ne $state.steam }
        Check 'latest-build answers' { $l = Invoke-RestMethod "http://127.0.0.1:$port/api/latest-build"; $null -ne $l.updateAvailable }
        Check 'starting a check without the header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/latest-build/check" -Method POST -Body '{}' -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
        Check 'app update status answers' { $null -ne (Invoke-RestMethod "http://127.0.0.1:$port/api/app/update-status").PSObject.Properties['state'] }
        Check 'latest-build includes this app''s version' { $null -ne (Invoke-RestMethod "http://127.0.0.1:$port/api/latest-build").app }
        Check 'starting an app update without the header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/app/update" -Method POST -Body '{}' -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
        Check 'network info answers' { $n = Invoke-RestMethod "http://127.0.0.1:$port/api/network"; $n.port -eq 30100 -and $n.protocol -eq 'UDP' }
        Check 'page html has the Network tab' { (Invoke-WebRequest "http://127.0.0.1:$port/" -UseBasicParsing).Content -match 'tab-network' }
        Check 'a wrong Host header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/state" -Headers @{ Host = 'evil.example' } -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
        Check 'a write without the header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/server/update" -Method POST -Body '{}' -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
        Check 'saving the Steam name without the header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/steam-user" -Method PUT -Body '{"user":"x"}' -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
    } finally { if ($ui -and -not $ui.HasExited) { Stop-Process -Id $ui.Id -Force } }

    Write-Host 'Packaging'
    $out = Join-Path ([IO.Path]::GetTempPath()) "wf2s-test-$([guid]::NewGuid().ToString('N'))"
    try {
        $zip = & "$PSScriptRoot\package.ps1" -Version 'test' -OutDir $out | Select-Object -Last 1
        Check 'zip built and contains no personal or game files' { Test-Path $zip }
    } finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }

    if (Test-Path (Join-Path $Server 'Wreckfest2.exe')) {
        Write-Host 'Game data (the game is installed)'
        Check 'game-data-report runs' { $null = & "$PSScriptRoot\game-data-report.ps1" *>&1; $true }
    } else { Write-Host 'Game data: skipped (game not installed)' }
} finally {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { Write-Host "`n$($script:fail) check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed." -ForegroundColor Green
