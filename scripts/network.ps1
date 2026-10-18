# What the host needs to know to let friends in, and which game build is installed. Dot-sourced by settings.ps1
# (uses Find-WfServerProcess and Invoke-WfConsole from apply.ps1, Read-WfJson from settings.ps1).

function Get-WfGamePort([string]$InstanceDir) {
    $port = 30100
    try {
        $cfg = Read-WfJson (Join-Path $InstanceDir 'server_config.template.scnf')
        $p = [int]$cfg.'net server config'[0].'game port'
        if ($p -gt 0 -and $p -lt 65536) { $port = $p }
    } catch { }
    $port
}

# This PC's address on the network the router hands out, the router's address, and whether the address is fixed.
function Get-WfLocalNetwork {
    $r = [ordered]@{ ip = ''; gateway = ''; adapter = ''; mac = ''; hostname = [string]$env:COMPUTERNAME; dhcp = $null }
    try {
        $cfg = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }) | Select-Object -First 1
        if ($cfg) {
            $r.ip = [string]@($cfg.IPv4Address)[0].IPAddress
            $r.gateway = [string]@($cfg.IPv4DefaultGateway)[0].NextHop
            $r.adapter = [string]$cfg.InterfaceAlias
            $r.mac = [string]$cfg.NetAdapter.MacAddress
            $iface = Get-NetIPInterface -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($iface) { $r.dhcp = ([string]$iface.Dhcp -eq 'Enabled') }
        }
    } catch { }
    $r
}

# Is the allow rule that scripts\firewall.ps1 makes present and enabled? ($null = could not tell)
function Test-WfFirewallRule([int]$Port) {
    try {
        $rules = @(Get-NetFirewallRule -DisplayName "Wreckfest 2 Server UDP $Port" -ErrorAction SilentlyContinue)
        return [bool]($rules | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' })
    } catch { return $null }
}

# 10.x, 172.16-31.x, 192.168.x, 169.254.x and 100.64-127.x (carrier-grade NAT) can't be reached from the internet by a port forward.
function Test-WfPrivateAddress([string]$Ip) {
    if ($Ip -notmatch '^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$') { return $null }
    $a = [int]$Matches[1]; $b = [int]$Matches[2]
    ($a -eq 10) -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or ($a -eq 192 -and $b -eq 168) -or ($a -eq 169 -and $b -eq 254) -or ($a -eq 100 -and $b -ge 64 -and $b -le 127)
}

# Reads the running server's own verdict from its console. The server tests this itself shortly after it starts and prints one of:
#   "Server is reachable from public network."   "Server is unreachable."
#   "Router port forwarded using UPnP. External endpoint at <ip:port>."   "Router port forwarding using UPnP unavailable..."
# (the exact texts come from the server program). status: running=$false (no server), 'reachable', 'unreachable', 'unknown' (no verdict printed yet).
function ConvertFrom-WfConsoleReachability([string[]]$Screen) {
    $r = [ordered]@{ status = 'unknown'; upnp = $null; endpoint = ''; address = ''; privateEndpoint = $false; lines = @() }
    $keep = @($Screen | Where-Object { $_ -match 'reachable|unreachable|UPnP|Server address set to' })
    $r.lines = @($keep | ForEach-Object { $_.Trim() } | Select-Object -Last 6)
    foreach ($l in $keep) {   # the last verdict on screen wins
        if ($l -match 'Server is reachable from public network') { $r.status = 'reachable' }
        elseif ($l -match 'Server is unreachable') { $r.status = 'unreachable' }
        if ($l -match 'forwarded using UPnP\. External endpoint at\s+([0-9.]+)(?::\d+)?') { $r.upnp = $true; $r.endpoint = $Matches[1] }
        elseif ($l -match 'UPnP unavailable') { $r.upnp = $false }
        if ($l -match 'Server address set to:\s*([0-9.]+)(?::\d+)?') { $r.address = $Matches[1] }   # the address the server advertises
    }
    # A private address here (10.x, 192.168.x, 100.64-127.x ...) means no port forward can work.
    $r.privateEndpoint = [bool](($r.endpoint -and (Test-WfPrivateAddress $r.endpoint)) -or ($r.address -and (Test-WfPrivateAddress $r.address)))
    $r
}

# The server prints its verdict once, a few seconds after it starts, and the console window then fills with other output
# (cars loading, chat) that pushes it out of view. So the verdict is remembered per server process.
$script:WfReachCache = @{}

function Get-WfReachability([string]$InstanceDir) {
    $r = [ordered]@{ running = $false; status = 'unknown'; upnp = $null; endpoint = ''; address = ''; privateEndpoint = $false; lines = @(); error = '' }
    $proc = Find-WfServerProcess $InstanceDir
    if (-not $proc) { return $r }
    $r.running = $true
    $key = "$($proc.ProcessId)-$($proc.CreationDate.Ticks)"
    try { $screen = @(Invoke-WfConsole ([int]$proc.ProcessId) @() 400) } catch { $r.error = $_.Exception.Message; return $r }
    $parsed = ConvertFrom-WfConsoleReachability $screen
    if ($parsed.status -ne 'unknown') { $script:WfReachCache[$key] = $parsed }
    elseif ($script:WfReachCache.ContainsKey($key)) { $parsed = $script:WfReachCache[$key] }
    foreach ($k in $parsed.Keys) { $r[$k] = $parsed[$k] }
    $r
}

function Get-WfNetworkInfo([string]$InstanceDir) {
    $port = Get-WfGamePort $InstanceDir
    $net = Get-WfLocalNetwork
    [ordered]@{
        port         = $port
        protocol     = 'UDP'
        local        = $net
        firewallRule = (Test-WfFirewallRule $port)
        reachability = (Get-WfReachability $InstanceDir)
    }
}

# ---- Game build -----------------------------------------------------------------------------------------------------------

# The Steam build id of the installed game server (steamapps\appmanifest_<app>.acf), or '' when not installed.
function Get-WfInstalledBuild([string]$ServerDir) {
    $f = Join-Path $ServerDir 'steamapps\appmanifest_3519390.acf'
    if (-not (Test-Path $f)) { return '' }
    if ([IO.File]::ReadAllText($f) -match '"buildid"\s+"(\d+)"') { return $Matches[1] }
    ''
}

# The build the page's game knowledge (names, lists, formats) was last checked against: defaults\known-build.json.
function Get-WfKnownBuild([string]$Root) {
    $f = Join-Path $Root 'defaults\known-build.json'
    if (Test-Path $f) { try { return Read-WfJson $f } catch { } }
    [pscustomobject]@{ buildid = ''; checked = '' }
}

function Get-WfBuildInfo([string]$Root, [string]$ServerDir) {
    $installed = Get-WfInstalledBuild $ServerDir
    $known = Get-WfKnownBuild $Root
    [ordered]@{
        installed    = $installed
        known        = [string]$known.buildid
        knownChecked = [string]$known.checked
        differs      = [bool]($installed -and $known.buildid -and $installed -ne [string]$known.buildid)
        steamUser    = (Get-WfSteamUser $Root)
    }
}

# Opens the update in its own visible window (SteamCMD may ask for a Steam Guard code) and returns at once; the page watches the build id.
function Start-WfUpdate([string]$Root) {
    $user = Get-WfSteamUser $Root
    if (-not $user) { throw 'No Steam account name is saved yet. Run scripts\install.ps1 -SteamUser <name> once, or Start.cmd to set up.' }
    $script = Join-Path $Root 'scripts\update.ps1'
    $launch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', ('"' + $script + '"'))
    $null = Start-Process powershell.exe -ArgumentList $launch -WorkingDirectory $Root
    [ordered]@{ started = $true; message = 'The update is running in its own window. Answer any Steam prompt there. When it says it is done, close it and start the server.' }
}
