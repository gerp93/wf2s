# Same as install; SteamCMD only downloads what changed. Stop the server first (the settings page's Update button does that).
# Uses the Steam account name saved by install.ps1.
& "$PSScriptRoot\install.ps1" @args
exit $LASTEXITCODE
