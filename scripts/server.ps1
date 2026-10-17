# Start and stop a server instance from the settings page. Dot-sourced by settings.ps1 (uses Find-WfServerProcess and
# Invoke-WfConsole from apply.ps1).
#
# Start runs the same command Hardpoint runs (powershell scripts\start.ps1) in its own minimized window, so the server keeps
# running when the page is closed and you can still type commands in that window.
# Stop types `shutdown` (the server's "graceful shutdown" console command, tested: it exits in about 2 seconds). If that
# does not work the page offers a force stop, which ends only that instance's Wreckfest2.exe.

function Start-WfServer([string]$Root, [string]$Instance, [switch]$Local) {
    $dir = Get-WfInstanceDir $Root $Instance
    if (Find-WfServerProcess $dir) { return [ordered]@{ running = $true; started = $false; message = 'The server is already running.' } }
    if (-not (Test-Path (Join-Path $Root 'server\Wreckfest2.exe'))) { throw 'The game server is not installed. Run scripts\install.ps1 first.' }
    if ((Test-Path (Join-Path $dir 'server_config.template.scnf')) -and -not (Test-Path (Join-Path $dir 'password.local'))) {
        throw 'No server password is set. Set one on the Password tab first.'
    }
    $launch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $Root 'scripts\start.ps1') + '"'), '-Instance', $Instance)
    if ($Local) { $launch += '-Local' }
    $launcher = Start-Process powershell.exe -ArgumentList $launch -WorkingDirectory $Root -WindowStyle Minimized -PassThru

    $proc = $null
    for ($i = 0; $i -lt 60 -and -not $proc; $i++) {
        Start-Sleep -Milliseconds 500
        $proc = Find-WfServerProcess $dir
        if (-not $proc -and $launcher.HasExited) {
            throw "start.ps1 stopped straight away (exit code $($launcher.ExitCode)). Run .\scripts\start.ps1 -Instance $Instance in a terminal to see why."
        }
    }
    if (-not $proc) { throw 'The server did not start within 30 seconds. Look at the minimized PowerShell window for the error.' }

    # The process exists almost at once, but the game needs a while (it verifies its data) before it prints "Server Started".
    $ready = $false
    for ($i = 0; $i -lt 20 -and -not $ready; $i++) {
        try { $ready = [bool](@(Invoke-WfConsole ([int]$proc.ProcessId) @() 80) -match 'Server Started') } catch { }
        if (-not $ready) { Start-Sleep -Seconds 2 }
    }
    [ordered]@{ running = $true; started = $true; ready = $ready
        message = $(if ($ready) { 'The server is up.' } else { 'The server started and is still loading. Give it a few more seconds before players join.' }) }
}

function Stop-WfServer([string]$InstanceDir, [switch]$Force) {
    $proc = Find-WfServerProcess $InstanceDir
    if (-not $proc) { return [ordered]@{ running = $false; stopped = $false; message = 'The server is not running.' } }
    $procId = [int]$proc.ProcessId
    $alive = { [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue) }

    if ($Force) {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20 -and (& $alive); $i++) { Start-Sleep -Milliseconds 250 }
        return [ordered]@{ running = (& $alive); stopped = -not (& $alive); message = 'The server was stopped by force.' }
    }

    $why = ''
    try { $null = Invoke-WfConsole $procId @('shutdown') 4 } catch { $why = $_.Exception.Message }
    for ($i = 0; $i -lt 40 -and (& $alive); $i++) { Start-Sleep -Milliseconds 500 }
    if (& $alive) {
        return [ordered]@{ running = $true; stopped = $false; stillRunning = $true
            message = $(if ($why) { "Could not ask the server to shut down ($why)." } else { 'The server did not stop within 20 seconds.' }) }
    }
    [ordered]@{ running = $false; stopped = $true; message = 'The server shut down.' }
}
