# Run ONCE in an elevated PowerShell. Opens the game port (default UDP 30100); pass more ports for extra instances.
param([int[]]$Ports = @(30100))
foreach ($p in $Ports) {
    New-NetFirewallRule -DisplayName "Wreckfest 2 Server UDP $p" -Direction Inbound -Protocol UDP -LocalPort $p -Action Allow -ErrorAction SilentlyContinue | Out-Null
}
