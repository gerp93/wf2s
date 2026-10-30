# Remote control of the settings page, over Tailscale. Dot-sourced by settings.ps1 (used by ui.ps1).
#
# How it fits together:
#   - The settings page always listens on 127.0.0.1:<Port> for this PC, with no login (as before).
#   - When remote access is switched on, ui.ps1 opens a SECOND listener, also on 127.0.0.1 only, on <remote port> (default 30181).
#     Everything that arrives there needs a login. Nothing ever listens on a network address, so no firewall rule is needed.
#   - Tailscale Serve (`tailscale serve`) forwards https://<this PC's Tailscale name> to that second listener. Tailscale itself
#     decides who can reach it (your access rules / who you shared the PC with); the password here is a second lock.
#   - One shared password, plus a name typed at sign-in so the activity log says who did what.
#
# Everything personal lives in the instance folder (instances\<name>\, gitignored): remote.json (switch, Tailscale name, ports),
# remote-password.local (a salted hash, never the password), activity-log.jsonl. Nothing here is ever committed or packaged.

# ---- configuration: instances\<name>\remote.json ----

function Test-WfRemoteHostName([string]$Name) { $Name -match '^[A-Za-z0-9]([A-Za-z0-9.\-]{0,251}[A-Za-z0-9])?$' }

function ConvertTo-WfRemoteHosts($Hosts) {
    $out = New-Object 'Collections.Generic.List[string]'
    foreach ($h in @($Hosts)) {
        if ($h -isnot [string]) { continue }
        $n = $h.Trim().TrimEnd('.').ToLowerInvariant()
        if ($n -eq '') { continue }
        if (-not (Test-WfRemoteHostName $n)) { throw "'$h' is not a valid host name." }
        if (-not $out.Contains($n)) { $out.Add($n) }
    }
    if ($out.Count -gt 10) { throw 'At most 10 host names.' }
    $out.ToArray()   # callers wrap the result in @()
}

function Get-WfRemoteConfig([string]$InstanceDir) {
    $cfg = [ordered]@{ enabled = $false; port = 30181; servePort = 443; hosts = @() }
    $f = Join-Path $InstanceDir 'remote.json'
    if (Test-Path $f) {
        try {
            $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json
            if ($j.enabled -is [bool]) { $cfg.enabled = $j.enabled }
            if ($j.port -is [int] -and $j.port -ge 1024 -and $j.port -le 65535) { $cfg.port = $j.port }
            if ($j.servePort -is [int] -and $j.servePort -ge 1 -and $j.servePort -le 65535) { $cfg.servePort = $j.servePort }
            $cfg.hosts = @(ConvertTo-WfRemoteHosts $j.hosts)
        } catch { }   # a damaged file means "off", never "on with guessed values"
    }
    [pscustomobject]$cfg
}

function Set-WfRemoteConfig([string]$InstanceDir, [bool]$Enabled, $Hosts, [int]$Port, [int]$ServePort, [int]$UiPort = 0) {
    if ($Port -lt 1024 -or $Port -gt 65535) { throw 'The remote port must be between 1024 and 65535.' }
    if ($Port -eq $UiPort) { throw "The remote port can't be the same as the settings page's own port ($UiPort)." }
    if ($ServePort -lt 1 -or $ServePort -gt 65535) { throw 'The Tailscale port must be between 1 and 65535.' }
    $h = @(ConvertTo-WfRemoteHosts $Hosts)
    $json = ConvertTo-Json -InputObject ([ordered]@{ enabled = $Enabled; port = $Port; servePort = $ServePort; hosts = $h }) -Depth 3
    [IO.File]::WriteAllText((Join-Path $InstanceDir 'remote.json'), $json, (New-Object Text.UTF8Encoding $false))
    Get-WfRemoteConfig $InstanceDir
}

# The Host header of a request to the remote listener must be one of the configured names (or loopback, which still needs the
# login). Blocks DNS rebinding and anything that reaches the listener under a name you did not set up.
function Test-WfRemoteHostHeader([string]$HostHeader, $Config) {
    $h = "$HostHeader".Trim().ToLowerInvariant()
    if ($h -notmatch '^(\[[^\]]+\]|[^:]+)(:\d+)?$') { return $false }
    $name = $Matches[1]
    ($name -eq '127.0.0.1') -or ($name -eq 'localhost') -or (@($Config.hosts) -contains $name)
}

# ---- the shared password: instances\<name>\remote-password.local (a salted PBKDF2 hash) ----

function Get-WfPbkdf2([string]$Password, [byte[]]$Salt, [int]$Iterations) {
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iterations, [Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $kdf.GetBytes(32) } finally { $kdf.Dispose() }
}
function Test-WfBytesEqual([byte[]]$A, [byte[]]$B) {   # no early exit, so the time taken doesn't reveal where they differ
    if ($A.Length -ne $B.Length) { return $false }
    $d = 0; for ($i = 0; $i -lt $A.Length; $i++) { $d = $d -bor ($A[$i] -bxor $B[$i]) }
    $d -eq 0
}
function New-WfPasswordHash([string]$Password) {
    $salt = New-Object byte[] 16
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider; try { $rng.GetBytes($salt) } finally { $rng.Dispose() }
    $iter = 100000
    ('pbkdf2-sha256', $iter, [Convert]::ToBase64String($salt), [Convert]::ToBase64String((Get-WfPbkdf2 $Password $salt $iter))) -join '$'
}
function Test-WfPasswordHash([string]$Password, [string]$Stored) {
    $p = "$Stored".Trim().Split('$')
    if ($p.Count -ne 4 -or $p[0] -ne 'pbkdf2-sha256' -or $p[1] -notmatch '^\d{4,7}$') { return $false }
    try { Test-WfBytesEqual (Get-WfPbkdf2 $Password ([Convert]::FromBase64String($p[2])) ([int]$p[1])) ([Convert]::FromBase64String($p[3])) } catch { $false }
}

function Test-WfRemotePasswordSet([string]$InstanceDir) { Test-Path (Join-Path $InstanceDir 'remote-password.local') }
function Set-WfRemotePassword([string]$InstanceDir, $Password) {
    if ($Password -isnot [string]) { throw 'Password must be text.' }
    $p = $Password.Trim()
    if ($p.Length -lt 8) { throw 'Use at least 8 characters.' }
    if ($p.Length -gt 128) { throw 'Password is too long (max 128 characters).' }
    if ($p -match '[\x00-\x1f]') { throw 'Password has control characters.' }
    [IO.File]::WriteAllText((Join-Path $InstanceDir 'remote-password.local'), (New-WfPasswordHash $p), (New-Object Text.UTF8Encoding $false))
    Clear-WfSessions   # everyone signed in with the old password is signed out
}
function Test-WfRemotePassword([string]$InstanceDir, $Password) {
    $f = Join-Path $InstanceDir 'remote-password.local'
    if ($Password -isnot [string] -or -not (Test-Path $f)) { return $false }
    Test-WfPasswordHash $Password.Trim() ([IO.File]::ReadAllText($f))
}

# ---- sign-in names, sessions and the lockout (all in memory: restarting the page signs everyone out) ----

function ConvertTo-WfPersonName($Name) {
    if ($Name -isnot [string]) { return $null }
    $n = ($Name.Trim() -replace '\s+', ' ')
    if ($n -match '^[\p{L}\p{N} ._\-]{1,32}$') { $n } else { $null }
}

$script:WfSessions = @{}
$script:WfSessionHours = 12
function New-WfToken { $b = New-Object byte[] 32; $r = New-Object Security.Cryptography.RNGCryptoServiceProvider; try { $r.GetBytes($b) } finally { $r.Dispose() }; ([Convert]::ToBase64String($b)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function New-WfSession([string]$Name) {
    $now = [DateTime]::UtcNow
    foreach ($k in @($script:WfSessions.Keys)) { if ($script:WfSessions[$k].expires -lt $now) { $script:WfSessions.Remove($k) } }
    while ($script:WfSessions.Count -ge 50) { $old = @($script:WfSessions.GetEnumerator() | Sort-Object { $_.Value.created })[0]; $script:WfSessions.Remove($old.Key) }
    $token = New-WfToken
    $script:WfSessions[$token] = [pscustomobject]@{ name = $Name; created = $now; expires = $now.AddHours($script:WfSessionHours) }
    $token
}
function Get-WfSession([string]$Token) {
    if (-not $Token -or -not $script:WfSessions.ContainsKey($Token)) { return $null }
    $s = $script:WfSessions[$Token]
    if ($s.expires -lt [DateTime]::UtcNow) { $script:WfSessions.Remove($Token); return $null }
    $s.expires = [DateTime]::UtcNow.AddHours($script:WfSessionHours)   # signed out after 12 idle hours
    $s
}
function Remove-WfSession([string]$Token) { if ($Token) { $script:WfSessions.Remove($Token) } }
function Clear-WfSessions { $script:WfSessions.Clear() }

# Five wrong passwords within ten minutes lock sign-in for everyone until the oldest of them is ten minutes old. There is no
# per-visitor address to count against (every request arrives from this PC), so the limit is global.
$script:WfLoginFailures = New-Object 'Collections.Generic.List[DateTime]'
function Get-WfLoginLockSeconds {
    $cut = [DateTime]::UtcNow.AddMinutes(-10)
    $null = $script:WfLoginFailures.RemoveAll([Predicate[DateTime]]{ param($t) $t -lt $cut })
    if ($script:WfLoginFailures.Count -lt 5) { return 0 }
    [int][Math]::Ceiling(($script:WfLoginFailures[0].AddMinutes(10) - [DateTime]::UtcNow).TotalSeconds)
}
function Add-WfLoginFailure { $script:WfLoginFailures.Add([DateTime]::UtcNow) }
function Clear-WfLoginFailures { $script:WfLoginFailures.Clear() }

# ---- activity log: instances\<name>\activity-log.jsonl, one JSON object per line ----

$script:WfActivityMaxBytes = 512KB   # past this size the file is cut back to its newest lines
$script:WfActivityKeepLines = 1000
function Add-WfActivity([string]$InstanceDir, [string]$Who, [string]$Action, [string]$Via = '') {
    $f = Join-Path $InstanceDir 'activity-log.jsonl'
    $entry = [ordered]@{ at = [DateTime]::UtcNow.ToString('o'); who = $Who; action = $Action }
    if ($Via) { $entry.via = $Via }
    $enc = New-Object Text.UTF8Encoding $false
    [IO.File]::AppendAllText($f, ((ConvertTo-Json -InputObject $entry -Compress) + "`n"), $enc)
    if ((Get-Item $f).Length -gt $script:WfActivityMaxBytes) {
        $lines = @([IO.File]::ReadAllLines($f, $enc))
        [IO.File]::WriteAllText($f, ((@($lines | Select-Object -Last $script:WfActivityKeepLines)) -join "`n") + "`n", $enc)
    }
}
# Newest first.
function Read-WfActivity([string]$InstanceDir, [int]$Limit = 200) {
    $f = Join-Path $InstanceDir 'activity-log.jsonl'
    if (-not (Test-Path $f)) { return @() }
    $out = New-Object 'Collections.Generic.List[object]'
    foreach ($line in @([IO.File]::ReadAllLines($f, (New-Object Text.UTF8Encoding $false)) | Select-Object -Last $Limit)) {
        try { $e = $line | ConvertFrom-Json; $at = if ($e.at -is [DateTime]) { $e.at.ToUniversalTime().ToString('o') } else { [string]$e.at }; $out.Add([pscustomobject]@{ at = $at; who = [string]$e.who; action = [string]$e.action; via = [string]$e.via }) } catch { }
    }
    $out.Reverse()
    $out.ToArray()   # callers wrap the result in @()
}

# What a mutating request is called in the log. $null = not worth logging (also: nothing is logged about the content of a request,
# so a password can never end up in the log).
function Get-WfActivityLabel([string]$Method, [string]$Path, [string]$Id = '', [bool]$Force = $false) {
    $safe = ($Id -replace '[^A-Za-z0-9_\-]', '')
    switch ("$Method $Path") {
        'PUT /api/overrides'        { 'Saved the Global defaults' }
        'PUT /api/loop'             { if ($safe -and $safe -ne 'main') { "Saved the events of cup '$safe'" } else { 'Saved the rotation' } }
        'PUT /api/cups'             { 'Saved the cups' }
        'POST /api/cup-loop'        { 'Created an event list for a cup' }
        'PUT /api/password'         { 'Changed the server password' }
        'POST /api/password/reveal' { 'Showed the server password' }
        'POST /api/server/start'    { 'Started the server' }
        'POST /api/server/stop'     { if ($Force) { 'Force-stopped the server' } else { 'Stopped the server' } }
        'POST /api/apply'           { 'Applied the saved settings to the running server' }
        'POST /api/server/update'   { 'Opened the server update window' }
        'POST /api/app/update'      { 'Updated the app' }
        'PUT /api/steam-user'       { 'Changed the Steam account name' }
        'PUT /api/remote'           { 'Changed the remote access settings' }
        'PUT /api/remote/password'  { 'Changed the remote access password' }
        'POST /api/remote/serve'    { 'Changed the Tailscale Serve setup' }
        default { $null }
    }
}

# ---- Tailscale ----

function Find-WfTailscale {
    foreach ($p in @((Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe'))) { if ($p -and (Test-Path $p)) { return $p } }
    $c = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $null
}

# Runs a program with fixed arguments and collects its output without letting a stderr line turn into a PowerShell error.
function Invoke-WfNative([string]$Exe, [string[]]$Arguments, [int]$TimeoutSeconds = 20) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe; $psi.Arguments = ($Arguments -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ code = -1; out = ''; err = 'Timed out.' } }
    [pscustomobject]@{ code = $p.ExitCode; out = $o.Result.Trim(); err = $e.Result.Trim() }
}

# This PC's Tailscale name and addresses, from `tailscale status --json`. Nothing is stored.
function Get-WfTailscaleInfo {
    $r = [ordered]@{ installed = $false; running = $false; dnsName = ''; ips = @() }
    $exe = Find-WfTailscale
    if (-not $exe) { return [pscustomobject]$r }
    $r.installed = $true
    try {
        $res = Invoke-WfNative $exe @('status', '--json') 10
        if ($res.code -eq 0) {
            $j = $res.out | ConvertFrom-Json
            $r.running = ($j.BackendState -eq 'Running')
            $r.dnsName = ([string]$j.Self.DNSName).TrimEnd('.').ToLowerInvariant()
            $r.ips = @($j.Self.TailscaleIPs | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
        }
    } catch { }
    [pscustomobject]$r
}

# Is Tailscale Serve already forwarding to the remote listener?
function Test-WfServeOn($Config) {
    $exe = Find-WfTailscale
    if (-not $exe) { return $false }
    try { $res = Invoke-WfNative $exe @('serve', 'status') 10; ($res.code -eq 0) -and ($res.out -match "(127\.0\.0\.1|localhost):$($Config.port)\b") } catch { $false }
}

# Switch the Serve forwarding on or off. Only touches the one HTTPS port named in the config.
function Set-WfServe([bool]$On, $Config) {
    $exe = Find-WfTailscale
    if (-not $exe) { throw 'Tailscale is not installed on this PC.' }
    $a = if ($On) { @('serve', '--bg', "--https=$($Config.servePort)", "http://127.0.0.1:$($Config.port)") } else { @('serve', "--https=$($Config.servePort)", 'off') }
    $res = Invoke-WfNative $exe $a 60
    if ($res.code -ne 0) { throw ("Tailscale said: " + (($res.err, $res.out | Where-Object { $_ }) -join ' ')) }
    $res.out
}
