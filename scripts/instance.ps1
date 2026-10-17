# Creating and preparing a server instance. Dot-sourced by settings.ps1 (uses Get-WfInstanceDir, Write-WfOverrides, Set-WfPassword).
#
# An instance is instances\<name>\ (the server's --save-dir). It is the host's own folder: created ONCE from defaults\instance
# and never overwritten afterwards, so updating the app never touches someone's config.

# Copies the clean default instance into instances\<name> when that instance has no config yet. Returns $true when it did.
# An instance that already has a server_config.template.scnf is left completely alone.
function Initialize-WfInstance([string]$Root, [string]$Instance) {
    $dir = Get-WfInstanceDir $Root $Instance
    $src = Join-Path $Root 'defaults\instance'
    if (-not (Test-Path (Join-Path $src 'server_config.template.scnf'))) { throw "The default instance is missing ($src). Re-download the app." }
    New-Item -ItemType Directory -Force $dir | Out-Null
    if (Test-Path (Join-Path $dir 'server_config.template.scnf')) { return $false }
    foreach ($f in Get-ChildItem $src -File) {
        $to = Join-Path $dir $f.Name
        if (-not (Test-Path $to)) { Copy-Item $f.FullName $to }
    }
    # The cup list starts as the six cups the game ships (also what "Reset to defaults" on the Cups tab goes back to).
    $cups = Join-Path $dir 'server_cup_config.template.ccnl'
    if (-not (Test-Path $cups)) { Copy-Item (Join-Path $Root 'defaults\server_cup_config.ccnl') $cups }
    $true
}

# The Steam account name used to download the game server. It is only a name (not a secret) and is kept so later updates
# don't have to ask again. Steam itself keeps the login; this app never sees or stores the password.
function Get-WfSteamUser([string]$Root) {
    $f = Join-Path $Root 'steam-user.local'
    if (Test-Path $f) { ([IO.File]::ReadAllText($f)).Trim() } else { '' }
}
function Set-WfSteamUser([string]$Root, [string]$User) {
    if ($User -notmatch '^[A-Za-z0-9_.\-]{2,64}$') { throw 'That does not look like a Steam account name (letters, digits, _ . - only).' }
    [IO.File]::WriteAllText((Join-Path $Root 'steam-user.local'), $User, (New-Object Text.UTF8Encoding $false))
}

# Accepts a SteamID64 (17 digits) or a steamcommunity.com/profiles/<id> link. Returns the 17-digit id, or $null.
# A custom-name link (steamcommunity.com/id/<name>) can't be turned into a number without Steam's web API, so it is not accepted.
function ConvertTo-WfSteamId([string]$Text) {
    $t = "$Text".Trim()
    if ($t -match '^7656119\d{10}$') { return $t }
    if ($t -match 'steamcommunity\.com/profiles/(7656119\d{10})') { return $Matches[1] }
    $null
}

# Adds admin Steam IDs to admins.local (one per line, no duplicates). They are read when server_privilege.sprv is first created.
function Add-WfAdmin([string]$InstanceDir, [string]$SteamId) {
    $id = ConvertTo-WfSteamId $SteamId
    if (-not $id) { throw "'$SteamId' is not a Steam ID (17 digits starting 7656119, or a steamcommunity.com/profiles/... link)." }
    $f = Join-Path $InstanceDir 'admins.local'
    $have = @(); if (Test-Path $f) { $have = @(Get-Content $f | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if ($have -notcontains $id) { [IO.File]::WriteAllText($f, ((@($have) + $id) -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false)) }
    $id
}

# Is the instance ready to start? Returns a list of plain-language problems (empty = ready).
function Get-WfInstanceProblems([string]$Root, [string]$Instance) {
    $problems = @()
    $dir = Get-WfInstanceDir $Root $Instance
    if (-not (Test-Path (Join-Path $Root 'server\Wreckfest2.exe'))) { $problems += 'The game server is not installed.' }
    if (-not (Test-Path (Join-Path $dir 'server_config.template.scnf'))) { $problems += 'The server has not been set up yet.' }
    elseif (-not (Test-WfPasswordSet $dir)) { $problems += 'No server password is set.' }
    $problems
}
