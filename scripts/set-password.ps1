# Usage: .\scripts\set-password.ps1 [-Instance main]
# Prompts for the server password and stores it in instances/<name>/password.local (gitignored).
# start.ps1 injects it into the generated server_config.scnf, so it never reaches git.
param([string]$Instance = 'main')
. "$PSScriptRoot\common.ps1"
$dir = Join-Path $Root "instances\$Instance"
New-Item -ItemType Directory -Force $dir | Out-Null
$secure = Read-Host 'Server password' -AsSecureString
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
[IO.File]::WriteAllText((Join-Path $dir 'password.local'), $plain, (New-Object Text.UTF8Encoding $false))
Add-WfPasswordHistory $dir 'set-password.ps1'
Write-Host "Saved to instances\$Instance\password.local (gitignored)."
