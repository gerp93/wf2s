# Usage: .\scripts\start.ps1 [-Instance main]
# Each instance = its own folder under ./instances (the --save-dir) with its own port.
# server_config.scnf is GENERATED each start from server_config.template.scnf (tracked) plus
# password.local (gitignored, see set-password.ps1). Edit the template, not the generated file.
param([string]$Instance = 'main')
. "$PSScriptRoot\common.ps1"
$save = Join-Path $Root "instances\$Instance"
if (-not (Test-Path $save)) { New-Item -ItemType Directory -Force $save | Out-Null }  # must exist before first launch

$template = Join-Path $save 'server_config.template.scnf'
$pwFile   = Join-Path $save 'password.local'
if (Test-Path $template) {
    if (-not (Test-Path $pwFile)) { throw "No password set. Run .\scripts\set-password.ps1 -Instance $Instance first." }
    $pw = (Get-Content $pwFile -Raw).Trim()
    $json = Get-Content $template -Raw | ConvertFrom-Json
    $json.'net server config'[0].password = $pw
    [IO.File]::WriteAllText((Join-Path $save 'server_config.scnf'), ($json | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
}

# server_privilege.sprv holds roles/bans and is changed at runtime, so it is only created when missing:
# template (tracked, no roles) + admins.local (gitignored, one SteamID64 per line).
$privTemplate = Join-Path $save 'server_privilege.template.sprv'
$priv         = Join-Path $save 'server_privilege.sprv'
if ((Test-Path $privTemplate) -and -not (Test-Path $priv)) {
    $json = Get-Content $privTemplate -Raw | ConvertFrom-Json
    $adminsFile = Join-Path $save 'admins.local'
    $ids = @()
    if (Test-Path $adminsFile) { $ids = @(Get-Content $adminsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }) }
    $json.roles = @($ids | ForEach-Object { [pscustomobject][ordered]@{ bbmeta = 'ssrl v0 n1'; 'platform id' = [long]$_; role = 'admin' } })
    [IO.File]::WriteAllText($priv, ($json | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
}

Set-Location $Server
& "$Server\Wreckfest2.exe" --server "--save-dir=$save"
