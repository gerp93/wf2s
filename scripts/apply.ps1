# Live apply: push saved settings to a RUNNING server without restarting it. Dot-sourced by settings.ps1.
#
# The server has no network remote control, but its console takes commands (`eventloop reload`, `cup reload`, ...), so
# console.ps1 types them into the server's console window. Findings from testing against a local-only test server:
#  - `eventloop reload` re-reads default_loop.becl and applies it (bots, laps, ...), but it also restarts the loop at its
#    first event and reloads the level. To avoid yanking the session to another track we jump back with `eventloop select`.
#  - `cup reload` re-reads the cup config, and the server refuses it while a cup is active.
#  - Server name, password, port and ban settings are only read at startup: those still need a restart.

# The running server for an instance: the Wreckfest2.exe whose command line has --save-dir=<this instance folder>.
function Find-WfServerProcess([string]$InstanceDir) {
    $full = [IO.Path]::GetFullPath($InstanceDir).TrimEnd('\')
    $pattern = '--save-dir="?' + [regex]::Escape($full) + '\\?("|\s|$)'
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='Wreckfest2.exe'")) {
        if ($p.CommandLine -match $pattern) { return $p }
    }
    $null
}

# Types commands into a server's console and returns the last $Read lines of its screen.
function Invoke-WfConsole([int]$ServerPid, [string[]]$Send, [int]$Read = 0) {
    $script = Join-Path $PSScriptRoot 'console.ps1'
    # An empty -SendList would be dropped when calling the exe and swallow the next argument, so only pass it when there is something to send.
    $extra = @(); if (@($Send).Count) { $extra += @('-SendList', ($Send -join '|')) }
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -ProcessId $ServerPid @extra -Read $Read 2>&1
    if ($LASTEXITCODE -ne 0 -or ($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) {
        $msg = (@($out) | ForEach-Object { "$_" } | Where-Object { $_.Trim() } | Select-Object -First 1)
        throw "Could not type into the server console: $msg"
    }
    @($out | ForEach-Object { "$_".TrimEnd(' ', '?', '@', 'A') })
}

# Lines of console output that came after the last time $Command was typed.
function Get-WfAfterCommand([string[]]$Lines, [string]$Command) {
    $last = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match ('^>\s*' + [regex]::Escape($Command) + '\s*$')) { $last = $i } }
    if ($last -lt 0) { return @() }
    @($Lines[($last + 1)..($Lines.Count - 1)])
}

function Invoke-WfApply([string]$InstanceDir, [string]$ServerDir) {
    $steps = New-Object 'Collections.Generic.List[string]'
    # 1. regenerate the files the game reads (same as start.ps1 does before launch)
    Build-WfLoop $InstanceDir
    Publish-WfCupLoops $InstanceDir $ServerDir
    $steps.Add('Wrote the rotation and cup files.')

    $proc = Find-WfServerProcess $InstanceDir
    if (-not $proc) {
        return [ordered]@{ running = $false; applied = $false; steps = @($steps)
            message = 'The server is not running. The files are updated and will be used the next time it starts.' }
    }
    $srvPid = [int]$proc.ProcessId

    # 2. which track is running now (the server prints the active event as JSON, including "eventId")
    $current = $null
    $screen = Invoke-WfConsole $srvPid @('event') 90
    foreach ($l in (Get-WfAfterCommand $screen 'event')) { if ($l -match '"eventId":\s*"([^"]+)"') { $current = $Matches[1] } }

    # 3. reload the rotation
    $screen = Invoke-WfConsole $srvPid @('eventloop reload') 30
    $after = Get-WfAfterCommand $screen 'eventloop reload'
    if (-not ($after -match "Event loop '.*' loaded")) {
        throw "The server did not confirm the reload. Its console said: $((@($after) | Select-Object -First 3) -join ' / ')"
    }
    $steps.Add('Reloaded the event rotation on the running server.')

    # 4. the reload restarts at the first event: go back to the track that was running, if it is still in the rotation
    $loop = Read-WfJson (Join-Path $InstanceDir 'default_loop.becl')
    $events = @($loop.events)
    $index = -1
    if ($current) { for ($i = 0; $i -lt $events.Count; $i++) { if ($events[$i].level[0].'level id' -eq $current) { $index = $i; break } } }
    if (-not $current) {
        $steps.Add('Could not tell which track was running, so the rotation restarted at its first track.')
    } elseif ($index -lt 0) {
        $steps.Add("The running track ($current) is switched off, so the rotation restarted at its first track.")
    } elseif ($index -gt 0) {
        Start-Sleep -Milliseconds 1800   # let the first level finish loading before selecting another
        $screen = Invoke-WfConsole $srvPid @("eventloop select $index") 12
        if (Get-WfAfterCommand $screen "eventloop select $index" | Where-Object { $_ -match '^Selected event' }) { $steps.Add("Went back to the running track ($current).") }
        else { $steps.Add("Tried to go back to the running track ($current) but the server did not confirm it.") }
    } else {
        $steps.Add("The running track ($current) is first in the rotation, so it stays selected.")
    }

    # 5. cups
    $screen = Invoke-WfConsole $srvPid @('cup reload') 8
    $cup = @(Get-WfAfterCommand $screen 'cup reload') -join ' '
    if ($cup -match 'Cup config reloaded') { $steps.Add('Reloaded the cup config.') }
    elseif ($cup -match 'cup is active') { $steps.Add('Cups were not reloaded because a cup is running. Apply again when it finishes.') }
    else { $steps.Add('Asked the server to reload the cup config; it did not say whether that worked.') }

    [ordered]@{ running = $true; applied = $true; currentTrack = $current; steps = @($steps)
        message = 'Applied to the running server. Name, password and ban settings still need a restart.' }
}
