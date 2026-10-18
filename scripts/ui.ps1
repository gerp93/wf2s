# Usage: .\scripts\ui.ps1 [-Instance main] [-Port 30180] [-LocalServer] [-OpenBrowser]
# Local settings page for a server instance. Serves ./ui on http://127.0.0.1:<Port> (this PC only) and
# reads/writes instances\<Instance>\settings.json. Changes apply the next time start.ps1 launches the server.
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

function Send($ctx, [int]$Status, [string]$Type, [byte[]]$Bytes) {
    $ctx.Response.StatusCode = $Status
    $ctx.Response.ContentType = $Type
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
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

function Handle($ctx) {
    $req  = $ctx.Request
    $path = $req.Url.AbsolutePath
    # Refuse anything not addressed to this machine by name (blocks DNS rebinding from other sites).
    if ($req.Headers['Host'] -notin @("127.0.0.1:$Port", "localhost:$Port")) { return SendJson $ctx 403 @{ error = 'Bad host.' } }

    if ($req.HttpMethod -eq 'GET' -and $static.ContainsKey($path)) {
        $s = $static[$path]
        return Send $ctx 200 $s.Type ([IO.File]::ReadAllBytes((Join-Path $uiDir $s.File)))
    }
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/state') {
        return SendJson $ctx 200 ([ordered]@{
            instance  = $Instance
            fields    = $WfFields
            overrides = Read-WfOverrides $save
            template  = (Get-TemplateValues)
            passwordSet = (Test-WfPasswordSet $save)
            passwordHistory = @(Read-WfPasswordHistory $save)
            running   = [bool](Find-WfServerProcess $save)   # this instance's own server, not just any Wreckfest2.exe
            build     = (Get-WfBuildInfo $Root $Server $save)
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
        try { $b = Read-Body $req; return SendJson $ctx 200 (Stop-WfServer $save -Force:([bool]$b.force)) }
        catch { return SendJson $ctx 500 @{ error = $_.Exception.Message } }
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

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Wreckfest 2 settings ($Instance): http://127.0.0.1:$Port/   (Ctrl+C to stop)"
if ($OpenBrowser) { try { Start-Process "http://127.0.0.1:$Port/" } catch { Write-Host 'Open that address in your browser.' } }
try {
    $pending = $listener.GetContextAsync()
    while ($true) {
        if (-not $pending.Wait(500)) { continue }   # poll so Ctrl+C works
        $ctx = $pending.Result
        $pending = $listener.GetContextAsync()
        try { Handle $ctx }
        catch { try { SendJson $ctx 500 @{ error = $_.Exception.Message } } catch { } }
    }
} finally { $listener.Stop() }
