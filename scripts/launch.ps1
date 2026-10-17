# What Start.cmd runs: sets the server up if something is missing, then runs the settings page and opens it in the browser.
# Closing this window stops the settings page only; a server started from the page keeps running in its own window.
param([string]$Instance = 'main', [int]$Port = 30180)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"

$problems = @(Get-WfInstanceProblems $Root $Instance)
if ($problems.Count) {
    Write-Host ('Setup is needed: ' + ($problems -join ' '))
    & "$PSScriptRoot\setup.ps1" -Instance $Instance
    $problems = @(Get-WfInstanceProblems $Root $Instance)
    if ($problems.Count) { Write-Warning ('Still missing: ' + ($problems -join ' ')); exit 1 }
}

# Already running (Start.cmd double-clicked twice)? Just open it again.
$url = "http://127.0.0.1:$Port/"
$up = $false
try { $null = Invoke-WebRequest "${url}api/state" -UseBasicParsing -TimeoutSec 2; $up = $true } catch { }
if ($up) { Write-Host "The settings page is already running: $url"; Start-Process $url; exit 0 }

& "$PSScriptRoot\ui.ps1" -Instance $Instance -Port $Port -OpenBrowser
