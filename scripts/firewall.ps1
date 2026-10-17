# Opens the game port (default UDP 30100) in Windows Firewall; pass more ports for extra instances. Needs an elevated
# PowerShell (setup.ps1 starts it elevated for you, with one Windows permission prompt). Safe to run again: a port that
# already has the rule is skipped.
param([int[]]$Ports = @(30100))
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Warning 'Run this in an elevated (Administrator) PowerShell.'; exit 1 }
foreach ($p in $Ports) {
    $name = "Wreckfest 2 Server UDP $p"
    if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { Write-Host "Already open: UDP $p"; continue }
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol UDP -LocalPort $p -Action Allow | Out-Null
    Write-Host "Opened UDP $p in Windows Firewall."
}
