# Usage: .\scripts\ui.ps1 [-Instance main] [-Port 30180] [-LocalServer] [-OpenBrowser]
# Local settings page for a server instance. Serves ./ui on http://127.0.0.1:<Port> (this PC only, no login) and
# reads/writes instances\<Instance>\settings.json. Changes apply the next time start.ps1 launches the server.
# With remote access switched on (instances\<Instance>\remote.json, see remote.ps1) it also serves the same page on a second
# loopback-only port, behind a password, for Tailscale Serve to forward to.
# -LocalServer makes the page's Start button launch the game's local-only mode (--local-server). It is for testing.
param([string]$Instance = 'main', [int]$Port = 30180, [switch]$LocalServer, [switch]$OpenBrowser)
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
$save  = Get-WfInstanceDir $Root $Instance
$uiDir = Join-Path $Root 'ui'
if (-not (Test-Path $save)) { throw "No instance folder at $save." }

# Only these files are ever served.
$static = @{
    '/'                                 = @{ File = 'index.html';                       Type = 'text/html; charset=utf-8' }
    '/vendor/visual-assault-themes.css' = @{ File = 'vendor\visual-assault-themes.css'; Type = 'text/css; charset=utf-8' }
}

$script:Remote = Get-WfRemoteConfig $save   # instances\<Instance>\remote.json
$script:Viewer = @{ remote = $false; name = 'This PC' }   # who the request being handled is from
$script:LastStatus = 0
$script:LogDetail = ''
$script:RemoteListener = $null; $script:RemoteListenerPort = 0; $script:PendingRemote = $null; $script:RemoteError = ''
# Only the always-local listener (this PC) may use these; the remote listener answers 403.
$hostOnly = @('/api/remote', '/api/remote/password', '/api/remote/serve', '/api/app/update', '/api/server/update', '/api/steam-user')

function Send($ctx, [int]$Status, [string]$Type, [byte[]]$Bytes) {
    $script:LastStatus = $Status
    $ctx.Response.StatusCode = $Status
    $ctx.Response.ContentType = $Type
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
    $ctx.Response.Headers['X-Content-Type-Options'] = 'nosniff'
    $ctx.Response.Headers['X-Frame-Options'] = 'DENY'
    $ctx.Response.Headers['Referrer-Policy'] = 'no-referrer'
    $ctx.Response.ContentLength64 = $Bytes.Length
    $ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $ctx.Response.Close()
}
function SendJson($ctx, [int]$Status, $Object) {
    Send $ctx $Status 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes(($Object | ConvertTo-Json -Depth 8)))
}

# What the templates currently say (first event / server config), so the page can show what "not overridden" means.
function Get-TemplateValues {
    $v = [ordered]@{}
    $varies = [ordered]@{}   # field -> distinct values across events, only when they differ
    $loopFile = Join-Path $save 'default_loop.template.becl'
    if (Test-Path $loopFile) {
        $events = @((Read-WfJson $loopFile).events | Where-Object { $_.disabled -ne $true })   # only events that will run
        foreach ($f in $WfFields) {
            $vals = switch ($f.Section) {
                'event'      { $events | ForEach-Object { $_.($f.Key) } }
                'event-ai'   { $events | ForEach-Object { $_.level[0].($f.Key) } }
                'event-rule' { $events | ForEach-Object { $_.rules[0].($f.Key) } }
                default      { $null }
            }
            if ($null -eq $vals) { continue }
            $v[$f.Key] = @($vals)[0]
            $distinct = @($vals | Sort-Object -Unique)
            if ($distinct.Count -gt 1) { $varies[$f.Key] = $distinct }
        }
    }
    $cfgFile = Join-Path $save 'server_config.template.scnf'
    if (Test-Path $cfgFile) {
        $cfg = Read-WfJson $cfgFile
        foreach ($f in $WfFields) {
            switch ($f.Section) {
                'net'    { $v[$f.Key] = $cfg.'net server config'[0].($f.Key) }
                'server' { $v[$f.Key] = $cfg.'game server config'[0].($f.Key) }
            }
        }
    }
    @{ values = $v; varies = $varies }
}

# The page's actual endpoints. Handle (below) has already decided who is asking and whether they may.
function Route($ctx) {
    $req  = $ctx.Request
    $path = $req.Url.AbsolutePath

    if ($req.HttpMethod -eq 'GET' -and $static.ContainsKey($path)) {
        $s = $static[$path]
        return Send $ctx 200 $s.Type ([IO.File]::ReadAllBytes((Join-Path $uiDir $s.File)))
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/state') {
        return SendJson $ctx 200 ([ordered]@{
            instance  = $Instance
            viewer    = $script:Viewer
            fields    = $WfFields
            overrides = Read-WfOverrides $save
            template  = (Get-TemplateValues)
            passwordSet = (Test-WfPasswordSet $save)
            passwordHistory = @(Read-WfPasswordHistory $save)
            running   = [bool](Find-WfServerProcess $save)   # this instance's own server, not just any Wreckfest2.exe
            build     = (Get-WfBuildInfo $Root $Server $save)
            steam     = (Get-WfSteamClient)
        })
    }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/overrides') {
        # A custom header can't be sent cross-origin without a CORS preflight (which this server never approves).
        if ($req.Headers['X-WF-UI'] -ne '1') { return SendJson $ctx 403 @{ error = 'Missing header.' } }
        try { $saved = Write-WfOverrides $save (Read-Body $req).overrides }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        return SendJson $ctx 200 @{ overrides = $saved }
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/network') {
        # Slow-ish (it reads the server console), so the page asks only when the Network tab is open or Refresh is clicked.
        try { return SendJson $ctx 200 (Get-WfNetworkInfo $save) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/app/update-status') {
        return SendJson $ctx 200 (Read-WfAppUpdateStatus $Root)
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/latest-build') {
        # The last answer from Steam about the newest server/game builds (read from a file; the check itself runs in the background).
        try { return SendJson $ctx 200 (Get-WfLatestBuild $Root $Server) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/activity') { return SendJson $ctx 200 @{ entries = @(Read-WfActivity $save 200) } }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/remote') { return SendJson $ctx 200 (Get-RemoteState) }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/choices') { return SendJson $ctx 200 (Get-WfChoices $save $Server) }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/loop') {
        try { return SendJson $ctx 200 (Read-WfLoop $save $req.QueryString['id']) }
        catch { return SendJson $ctx 404 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/cups') {
        # defaults: the game's own cups as shipped, by id, for "Reset to defaults".
        return SendJson $ctx 200 ([ordered]@{ cups = @((Read-WfCups $save).cups); defaults = (Get-WfDefaultCups) })
    }

    # Everything below changes files: same cross-origin guard as above.
    if ($req.HttpMethod -in 'PUT', 'POST' -and $req.Headers['X-WF-UI'] -ne '1') { return SendJson $ctx 403 @{ error = 'Missing header.' } }
    if ($req.HttpMethod -in 'PUT', 'POST' -and $req.ContentLength64 -gt 4MB) { return SendJson $ctx 413 @{ error = 'Too large.' } }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/loop') {
        try { Save-WfLoop $save $req.QueryString['id'] (Read-Body $req) }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        return SendJson $ctx 200 @{ saved = $true }
    }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/cups') {
        try { Save-WfCups $save (Read-Body $req) }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        return SendJson $ctx 200 @{ saved = $true }
    }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/remote') {
        # Switch remote access on or off and set the Tailscale name(s) it answers to.
        try {
            $b = Read-Body $req
            $hosts = if ($null -ne $b.hosts) { $b.hosts } else { $script:Remote.hosts }
            $enabled = [bool]$b.enabled
            if ($enabled -and -not (Test-WfRemotePasswordSet $save)) { throw 'Set the remote password first.' }
            $script:Remote = Set-WfRemoteConfig $save $enabled $hosts $script:Remote.port $script:Remote.servePort $Port
        } catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        Sync-RemoteListener
        return SendJson $ctx 200 (Get-RemoteState)
    }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/remote/password') {
        # The new value is never logged or echoed back. Everyone signed in with the old one is signed out.
        try { Set-WfRemotePassword $save (Read-Body $req).password }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        Sync-RemoteListener
        return SendJson $ctx 200 (Get-RemoteState)
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/remote/serve') {
        # Runs `tailscale serve` to forward the Tailscale name to the remote listener (or removes that forwarding).
        try {
            $on = [bool](Read-Body $req).on
            if ($on -and -not $script:RemoteListener) { throw 'Switch remote access on first (it needs a password).' }
            $null = Set-WfServe $on $script:Remote
        } catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        return SendJson $ctx 200 (Get-RemoteState)
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/password/reveal') {
        # Only when the Show button is clicked (POST + the custom header the guard above requires, so another website can't
        # trigger it, and no CORS headers are sent, so it couldn't read the answer anyway). Never logged or cached.
        return SendJson $ctx 200 @{ password = (Get-WfPassword $save) }
    }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/password') {
        # The new value is never logged or echoed back.
        try { Set-WfPassword $save (Read-Body $req).password }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        return SendJson $ctx 200 @{ passwordSet = $true; history = @(Read-WfPasswordHistory $save) }
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/server/start') {
        # Runs scripts\start.ps1 for this instance (the same command Hardpoint runs), then waits for the server to come up.
        try { return SendJson $ctx 200 (Start-WfServer $Root $Instance -Local:$LocalServer) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/server/stop') {
        # Graceful: types `shutdown` into the server console. With {"force": true} it ends this instance's process instead.
        try { $b = Read-Body $req; if ($b.force) { $script:LogDetail = 'force' }; return SendJson $ctx 200 (Stop-WfServer $save -Force:([bool]$b.force)) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/app/update') {
        # Replaces this app's files with the newest release (scripts\self-update.ps1) and restarts this page. Takes no input: the
        # download address comes from the last check, never from the request.
        try { return SendJson $ctx 200 (Start-WfAppUpdate $Root $Instance $Port) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/latest-build/check') {
        # Starts scripts\check-update.ps1 in the background (anonymous, read-only question to Steam) and returns at once.
        try { return SendJson $ctx 200 (Start-WfLatestBuildCheck $Root $Server) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'PUT' -and $path -eq '/api/steam-user') {
        # Only the account NAME (never a password): it is what the Update server button gives SteamCMD, which asks for the rest itself.
        try { Set-WfSteamUser $Root ([string](Read-Body $req).user) }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
        return SendJson $ctx 200 (Get-WfBuildInfo $Root $Server $save)
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/server/update') {
        # Opens scripts\update.ps1 in its own window (SteamCMD may ask for a Steam Guard code). The server must be stopped first.
        try {
            if (Find-WfServerProcess $save) { return SendJson $ctx 409 @{ error = 'Stop the server first.' } }
            return SendJson $ctx 200 (Start-WfUpdate $Root)
        } catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/apply') {
        # Push the saved settings to this instance's running server (see apply.ps1).
        try { return SendJson $ctx 200 (Invoke-WfApply $save $Server) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/cup-loop') {
        # New custom loop for a cup, copied from the main rotation. Returns the path to put in the cup's 'event loop'.
        # {name, cloneOf: <slug>} copies a custom cup's events; {name, from: <game cup loop path>} starts from a built-in cup.
        try {
            $b = Read-Body $req
            $path = if ($b.cloneOf) { Copy-WfCupLoop $save ([string]$b.name) ([string]$b.cloneOf) } else { New-WfCupLoop $save ([string]$b.name) $Server ([string]$b.from) }
            return SendJson $ctx 200 @{ path = $path }
        }
        catch { return SendJson $ctx 400 @{ error = $_.Exception.Message } }
    }
    SendJson $ctx 404 @{ error = 'Not found.' }
}

function Read-Body($req) { (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json }

# ---- remote access (see remote.ps1) ----

function Get-RemoteState {
    $cfg = $script:Remote
    [ordered]@{
        config      = $cfg
        passwordSet = (Test-WfRemotePasswordSet $save)
        listening   = [bool]$script:RemoteListener
        listenError = $script:RemoteError
        tailscale   = (Get-WfTailscaleInfo)
        serveOn     = (Test-WfServeOn $cfg)
        uiPort      = $Port
    }
}

# Opens or closes the password-protected listener to match remote.json. Never opens without a password. Loopback only.
function Sync-RemoteListener {
    $want = $script:Remote.enabled -and (Test-WfRemotePasswordSet $save)
    if ($script:RemoteListener -and (-not $want -or $script:RemoteListenerPort -ne $script:Remote.port)) {
        $script:PendingRemote = $null
        try { $script:RemoteListener.Stop(); $script:RemoteListener.Close() } catch { }
        $script:RemoteListener = $null
        Clear-WfSessions
    }
    $script:RemoteError = ''
    if ($want -and -not $script:RemoteListener) {
        try {
            $l = New-Object Net.HttpListener
            $l.Prefixes.Add("http://127.0.0.1:$($script:Remote.port)/")
            $l.Start()
            $script:RemoteListener = $l; $script:RemoteListenerPort = $script:Remote.port
            $script:PendingRemote = $l.GetContextAsync()
            Write-Host "Remote access: password-protected page on http://127.0.0.1:$($script:Remote.port)/ (for Tailscale Serve; not reachable from the network by itself)"
        } catch { $script:RemoteError = "Could not listen on port $($script:Remote.port): $($_.Exception.Message)"; Write-Warning $script:RemoteError }
    } elseif ($script:Remote.enabled -and -not $want) {
        $script:RemoteError = 'Remote access is on but no password is set, so it stays closed.'
    }
}

function Write-Log([string]$Who, [string]$Action, [string]$Via = '') {
    try { Add-WfActivity $save $Who $Action $Via } catch { }   # a log problem must never break the request
}

# Sign in: name + the shared password. Wrong passwords are counted and, after five, everyone waits (see Get-WfLoginLockSeconds).
function Invoke-Login($ctx, [string]$Via) {
    $req = $ctx.Request
    if ($req.Headers['X-WF-UI'] -ne '1') { return SendJson $ctx 403 @{ error = 'Missing header.' } }
    if ($req.ContentLength64 -gt 4096) { return SendJson $ctx 413 @{ error = 'Too large.' } }
    $lock = Get-WfLoginLockSeconds
    if ($lock -gt 0) {
        $ctx.Response.Headers['Retry-After'] = [string]$lock
        return SendJson $ctx 429 @{ error = "Too many wrong passwords. Try again in $([Math]::Ceiling($lock / 60)) minute(s)." }
    }
    try { $b = Read-Body $req } catch { return SendJson $ctx 400 @{ error = 'Bad request.' } }
    $name = ConvertTo-WfPersonName $b.name
    if (-not $name) { return SendJson $ctx 400 @{ error = 'Type your name (letters, digits, spaces, . _ -, up to 32 characters).' } }
    if (-not (Test-WfRemotePassword $save $b.password)) {
        Add-WfLoginFailure
        Write-Log "$name (remote)" 'Wrong password at sign-in' $Via
        return SendJson $ctx 401 @{ error = 'Wrong password.' }
    }
    Clear-WfLoginFailures
    $token = New-WfSession $name
    $secure = if ($req.Headers['X-Forwarded-Proto'] -eq 'https') { '; Secure' } else { '' }
    $ctx.Response.AppendHeader('Set-Cookie', "wf_session=$token; Path=/; HttpOnly; SameSite=Strict; Max-Age=$($script:WfSessionHours * 3600)$secure")
    Write-Log "$name (remote)" 'Signed in' $Via
    SendJson $ctx 200 @{ name = $name }
}

# Every request lands here. Who is asking decides what happens next: this PC (no login) or the remote listener (login required).
function Handle($ctx, [bool]$IsRemote) {
    $req  = $ctx.Request
    $path = $req.Url.AbsolutePath
    $script:LastStatus = 0; $script:LogDetail = ''
    $who = 'This PC'; $via = ''

    if (-not $IsRemote) {
        # Refuse anything not addressed to this machine by name (blocks DNS rebinding from other sites).
        if ($req.Headers['Host'] -notin @("127.0.0.1:$Port", "localhost:$Port")) { return SendJson $ctx 403 @{ error = 'Bad host.' } }
        $script:Viewer = @{ remote = $false; name = 'This PC' }
    } else {
        if (-not (Test-WfRemoteHostHeader $req.Headers['Host'] $script:Remote)) { return SendJson $ctx 403 @{ error = 'Bad host.' } }
        # Tailscale Serve adds the visitor's Tailscale login. It is only written to the log as extra information, never trusted.
        $via = ("$($req.Headers['Tailscale-User-Login'])" -replace '[^\x20-\x7e]', '')
        if ($via.Length -gt 100) { $via = $via.Substring(0, 100) }

        if ($req.HttpMethod -eq 'GET' -and $path -eq '/vendor/visual-assault-themes.css') { return Route $ctx }   # the sign-in page needs the theme
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/login') { return Invoke-Login $ctx $via }
        $cookie = $req.Cookies['wf_session']
        $session = if ($cookie) { Get-WfSession $cookie.Value } else { $null }
        if (-not $session) {
            if ($req.HttpMethod -eq 'GET' -and $path -eq '/') { return Send $ctx 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes((Join-Path $uiDir 'login.html'))) }
            return SendJson $ctx 401 @{ error = 'Sign in first.' }
        }
        if ($req.HttpMethod -eq 'POST' -and $path -eq '/api/logout') {
            if ($req.Headers['X-WF-UI'] -ne '1') { return SendJson $ctx 403 @{ error = 'Missing header.' } }
            Remove-WfSession $cookie.Value
            $ctx.Response.AppendHeader('Set-Cookie', 'wf_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0')
            Write-Log "$($session.name) (remote)" 'Signed out' $via
            return SendJson $ctx 200 @{ signedOut = $true }
        }
        if ($path -in $hostOnly) { return SendJson $ctx 403 @{ error = 'That can only be done on the PC that runs the server.' } }
        $who = "$($session.name) (remote)"
        $script:Viewer = @{ remote = $true; name = $session.name }
    }

    $id = if ($req.QueryString) { [string]$req.QueryString['id'] } else { '' }   # read now: the request can't be asked after it was answered
    $method = $req.HttpMethod
    Route $ctx
    if ($method -in 'PUT', 'POST' -and $script:LastStatus -ge 200 -and $script:LastStatus -lt 300) {
        $label = Get-WfActivityLabel $method $path $id ($script:LogDetail -eq 'force')
        if ($label) { Write-Log $who $label $via }
    }
}

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Wreckfest 2 settings ($Instance): http://127.0.0.1:$Port/   (Ctrl+C to stop)"
Sync-RemoteListener
if ($OpenBrowser) { try { Start-Process "http://127.0.0.1:$Port/" } catch { Write-Host 'Open that address in your browser.' } }
try {
    $pendingLocal = $listener.GetContextAsync()
    while ($true) {
        $tasks = @($pendingLocal); if ($script:PendingRemote) { $tasks += $script:PendingRemote }
        $i = [Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]$tasks, 500)   # a timeout, so Ctrl+C works
        if ($i -lt 0) { continue }
        $isRemote = ($i -eq 1)
        if ($isRemote) {
            try { $ctx = $tasks[1].Result } catch { $script:PendingRemote = $null; continue }   # that listener was closed
            $script:PendingRemote = $script:RemoteListener.GetContextAsync()
        } else {
            $ctx = $pendingLocal.Result
            $pendingLocal = $listener.GetContextAsync()
        }
        try { Handle $ctx $isRemote }
        catch {
            Write-Warning "Request failed: $($_.Exception.Message)"
            try { SendJson $ctx 500 @{ error = $_.Exception.Message } } catch { }
        }
    }
} finally {
    $listener.Stop()
    if ($script:RemoteListener) { try { $script:RemoteListener.Stop() } catch { } }
}
