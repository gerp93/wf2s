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
    Check 'game port read'              { (Get-WfGamePort $dir) -eq 30100 }
    Check 'known build file readable'   { (Get-WfKnownBuild $Root).buildid -match '^\d+$' }

    Write-Host 'Settings page'
    $port = 30190 + (Get-Random -Maximum 9)
    $ui = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'ui.ps1') + '"'), '-Instance', $name, '-Port', $port)
    try {
        $state = $null
        for ($i = 0; $i -lt 30 -and -not $state; $i++) { Start-Sleep -Milliseconds 500; try { $state = Invoke-RestMethod "http://127.0.0.1:$port/api/state" } catch { } }
        Check 'page answers' { $state.instance -eq $name }
        Check 'state has build info' { $null -ne $state.build }
        Check 'password is not in the state' { -not ((ConvertTo-Json $state -Depth 6) -match 'ci-test-password') }
        Check 'network info answers' { $n = Invoke-RestMethod "http://127.0.0.1:$port/api/network"; $n.port -eq 30100 -and $n.protocol -eq 'UDP' }
        Check 'page html has the Network tab' { (Invoke-WebRequest "http://127.0.0.1:$port/" -UseBasicParsing).Content -match 'tab-network' }
        Check 'a wrong Host header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/state" -Headers @{ Host = 'evil.example' } -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
        Check 'a write without the header is refused' { try { $null = Invoke-WebRequest "http://127.0.0.1:$port/api/server/update" -Method POST -Body '{}' -UseBasicParsing; $false } catch { $_.Exception.Response.StatusCode.value__ -eq 403 } }
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
