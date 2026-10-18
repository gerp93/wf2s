# Downloads SteamCMD (if missing) and installs/updates the Wreckfest 2 dedicated server into ./server. Safe to run again.
# Usage: .\scripts\install.ps1 [-SteamUser <name>]
# Anonymous login is refused for this app ("Missing configuration"), so pass an account that owns Wreckfest 2. The name is
# remembered in steam-user.local (gitignored; it is only a name), so later runs and updates don't need it again.
# SteamCMD prompts for the password / Steam Guard itself; this app never sees or stores them.
# Exit code: 0 = the server is installed and up to date, 1 = it failed.
param([string]$SteamUser = '')
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
if (-not $SteamUser) { $SteamUser = Get-WfSteamUser $Root }
if (-not $SteamUser) {
    Write-Warning 'No Steam account name given. Anonymous login is refused for this game, so this will most likely fail.'
    Write-Warning 'Use: .\scripts\install.ps1 -SteamUser YOUR_STEAM_USERNAME'
    $SteamUser = 'anonymous'
}
if (-not (Test-Path "$SteamCmd\steamcmd.exe")) {
    New-Item -ItemType Directory -Force $SteamCmd | Out-Null
    $zip = Join-Path $env:TEMP 'steamcmd.zip'
    Write-Host 'Downloading SteamCMD from Valve...'
    Invoke-WebRequest 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile $zip
    Expand-Archive $zip $SteamCmd -Force
    Remove-Item $zip -ErrorAction SilentlyContinue
}
Write-Host "Installing or updating the Wreckfest 2 dedicated server into $Server (a large download the first time)."
for ($try = 1; $try -le 2; $try++) {
    # SteamCMD updates itself on its very first run and can exit with an error code then; one retry covers that.
    & "$SteamCmd\steamcmd.exe" +force_install_dir $Server +login $SteamUser +app_update $AppId validate +quit
    if ($LASTEXITCODE -eq 0 -and (Test-Path "$Server\Wreckfest2.exe")) { break }
    if ($try -eq 1) { Write-Host 'SteamCMD did not finish cleanly. Trying once more...' }
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$Server\Wreckfest2.exe")) {
    Write-Warning "SteamCMD failed (exit $LASTEXITCODE). See the output above. Common causes: wrong password or Steam Guard code, or the account does not own Wreckfest 2."
    exit 1
}
if ($SteamUser -ne 'anonymous') { Set-WfSteamUser $Root $SteamUser }
Write-Host "Done. Installed build: $(Get-WfInstalledBuild $Server)"
exit 0
