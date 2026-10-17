# Usage: .\scripts\start.ps1 [-Instance main]
# Each instance = its own folder under ./instances (the --save-dir) with its own port.
# server_config.scnf is GENERATED each start from server_config.template.scnf (tracked) plus
# password.local (gitignored, see set-password.ps1). Edit the template, not the generated file.
# default_loop.becl is generated the same way from default_loop.template.becl.
# -Local starts the game's local-only mode (--local-server) instead of the normal online one (--server). It is for testing.
param([string]$Instance = 'main', [switch]$Local)
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
$save = Join-Path $Root "instances\$Instance"
if (-not (Test-Path $save)) { New-Item -ItemType Directory -Force $save | Out-Null }  # must exist before first launch

# settings.json (edited by scripts\ui.ps1) overrides values in the templates below; see settings.ps1.
$overrides = Read-WfOverrides $save

$template = Join-Path $save 'server_config.template.scnf'
$pwFile   = Join-Path $save 'password.local'
if (Test-Path $template) {
    if (-not (Test-Path $pwFile)) { throw "No password set. Run .\scripts\set-password.ps1 -Instance $Instance first." }
    $pw = (Get-Content $pwFile -Raw).Trim()
    $json = Read-WfJson $template
    Set-WfServerOverrides $json $overrides
    $json.'net server config'[0].password = $pw
    [IO.File]::WriteAllText((Join-Path $save 'server_config.scnf'), ($json | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
}

# default_loop.becl is generated from default_loop.template.becl plus the overrides.
Build-WfLoop $save

# Custom cup loops (instances\<name>\cups\*.becl) must sit in the game's own cup folder; copy them there.
Publish-WfCupLoops $save $Server

# server_privilege.sprv holds roles/bans and is changed at runtime, so it is only created when missing:
# template (tracked, no roles) + admins.local (gitignored, one SteamID64 per line).
$privTemplate = Join-Path $save 'server_privilege.template.sprv'
$priv         = Join-Path $save 'server_privilege.sprv'
if ((Test-Path $privTemplate) -and -not (Test-Path $priv)) {
    $json = Read-WfJson $privTemplate
    $adminsFile = Join-Path $save 'admins.local'
    $ids = @()
    if (Test-Path $adminsFile) { $ids = @(Get-Content $adminsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }) }
    $json.roles = @($ids | ForEach-Object { [pscustomobject][ordered]@{ bbmeta = 'ssrl v0 n1'; 'platform id' = [long]$_; role = 'admin' } })
    [IO.File]::WriteAllText($priv, ($json | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
}

Set-Location $Server
$mode = if ($Local) { '--local-server' } else { '--server' }
& "$Server\Wreckfest2.exe" $mode "--save-dir=$save"
