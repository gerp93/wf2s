# Shared paths. Dot-source from other scripts: . "$PSScriptRoot\common.ps1"
$Root     = Split-Path $PSScriptRoot -Parent
$SteamCmd = Join-Path $Root 'steamcmd'
$Server   = Join-Path $Root 'server'
$AppId    = 3519390   # Wreckfest 2 Dedicated Server
