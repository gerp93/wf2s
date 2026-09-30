# Downloads SteamCMD (if missing) and installs/updates the Wreckfest 2 dedicated server into ./server
# Usage: .\scripts\install.ps1 [-SteamUser <name>]
# Anonymous login is refused for this app ("Missing configuration"), so pass an account that owns Wreckfest 2.
# SteamCMD prompts for the password / Steam Guard itself; nothing is stored in this repo.
param([string]$SteamUser = 'anonymous')
. "$PSScriptRoot\common.ps1"
if (-not (Test-Path "$SteamCmd\steamcmd.exe")) {
    New-Item -ItemType Directory -Force $SteamCmd | Out-Null
    $zip = Join-Path $env:TEMP 'steamcmd.zip'
    Invoke-WebRequest 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile $zip
    Expand-Archive $zip $SteamCmd -Force
}
& "$SteamCmd\steamcmd.exe" +force_install_dir $Server +login $SteamUser +app_update $AppId validate +quit
if ($LASTEXITCODE -ne 0) { Write-Warning "SteamCMD failed (exit $LASTEXITCODE). See output above." }
