# First-run setup. Start.cmd runs this when something is missing; you can also run it yourself. Safe to run again:
# every step that is already done is skipped, and an existing server's name, password and settings are only changed if you type new ones.
#
#   1. checks the PC
#   2. downloads the game server (SteamCMD; asks for your Steam account name, Steam asks for the password)
#   3. asks for the server name, the server password and your Steam ID (you become the server's admin)
#   4. creates your server folder instances\<name> from defaults\instance
#   5. opens the game port in Windows Firewall (one Windows permission prompt)
#   6. tells you what to do on your router
#
# The parameters are for scripted/test runs; normally you just answer the questions.
param(
    [string]$Instance = 'main',
    [string]$SteamUser = '',
    [string]$ServerName = '',
    [securestring]$Password,
    [string]$AdminSteamId = '',
    [switch]$SkipInstall,
    [switch]$SkipFirewall,
    [switch]$NoPrompt        # never ask; fail with a message if an answer is needed and was not given
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"

function Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Ask([string]$Question, [string]$Default = '') {
    if ($NoPrompt) { return $Default }
    $hint = if ($Default) { " [$Default]" } else { '' }
    $a = (Read-Host "$Question$hint").Trim()
    if ($a) { $a } else { $Default }
}
function AskYesNo([string]$Question, [bool]$Default = $true) {
    if ($NoPrompt) { return $Default }
    $a = (Read-Host "$Question $(if ($Default) { '(Y/n)' } else { '(y/N)' })").Trim().ToLower()
    if (-not $a) { return $Default }
    $a.StartsWith('y')
}
function ToPlain([securestring]$s) { [Net.NetworkCredential]::new('', $s).Password }

Write-Host 'Wreckfest 2 dedicated server: setup' -ForegroundColor Green

# ---- 1. The PC ---------------------------------------------------------------------------------------------------------
Step '1 of 6: checking this PC'
if ($env:OS -ne 'Windows_NT') { throw 'The Wreckfest 2 server only runs on Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 5) { throw "This needs Windows PowerShell 5 or newer (you have $($PSVersionTable.PSVersion))." }
if ($Root -match '\.zip') { throw 'This folder is still inside the downloaded zip file. Right-click the zip, choose Extract All, and run Start.cmd from the extracted folder.' }
$serverInstalled = Test-Path (Join-Path $Server 'Wreckfest2.exe')
if (-not $serverInstalled -and -not $SkipInstall) {
    try {
        $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Root))).AvailableFreeSpace
        if ($free -lt 6GB) { throw ("Only {0:N1} GB is free on {1}. The game server needs about 6 GB. Free some space or move this folder to another drive." -f ($free / 1GB), [IO.Path]::GetPathRoot($Root)) }
        Write-Host ("Free disk space: {0:N1} GB. OK." -f ($free / 1GB))
    } catch [System.ArgumentException] { Write-Host 'Could not check free disk space (network folder?). Continuing.' }
}
Write-Host "Windows and PowerShell $($PSVersionTable.PSVersion): OK."

# ---- 2. The game server ------------------------------------------------------------------------------------------------
Step '2 of 6: the game server'
if ($serverInstalled) {
    Write-Host "Already installed (build $(Get-WfInstalledBuild $Server)). Skipping."
} elseif ($SkipInstall) {
    Write-Host 'Skipped (-SkipInstall).'
} else {
    Write-Host 'The game server is downloaded with SteamCMD, Valve''s command-line Steam client. You need a Steam account that owns'
    Write-Host 'Wreckfest 2. Type the account NAME (the one you sign in with) here; SteamCMD then asks for your password and a'
    Write-Host 'Steam Guard code if you use one. You type those into this window and they go straight to Steam: this app never sees them.'
    $saved = Get-WfSteamUser $Root
    if (-not $SteamUser) { $SteamUser = Ask 'Steam account name' $saved }
    if (-not $SteamUser) { throw 'A Steam account name is needed to download the game server.' }
    Set-WfSteamUser $Root $SteamUser   # throws on a name that can't be a Steam account
    do {
        & "$PSScriptRoot\install.ps1" -SteamUser $SteamUser
        $serverInstalled = Test-Path (Join-Path $Server 'Wreckfest2.exe')
        if (-not $serverInstalled) {
            if (-not (AskYesNo 'The download did not finish. Try again?')) { throw 'The game server is not installed. Run Start.cmd again when you are ready.' }
        }
    } while (-not $serverInstalled)
}

# ---- 3 + 4. Your server ------------------------------------------------------------------------------------------------
Step '3 of 6: your server'
$dir = Get-WfInstanceDir $Root $Instance
$created = Initialize-WfInstance $Root $Instance
if ($created) { Write-Host "Created your server folder: instances\$Instance" } else { Write-Host "Using your existing server folder: instances\$Instance" }

# Name
$overrides = Read-WfOverrides $dir
$currentName = if ($overrides.Contains('name')) { [string]$overrides['name'] } else { [string](Read-WfJson (Join-Path $dir 'server_config.template.scnf')).'net server config'[0].name }
if (-not $ServerName) { $ServerName = Ask 'Server name (shown in the game''s server list)' $currentName }
if ($ServerName -ne $currentName) {
    $overrides['name'] = $ServerName
    $null = Write-WfOverrides $dir $overrides   # validates length and characters
    Write-Host "Server name: $ServerName"
}

# Password
$hasPassword = Test-WfPasswordSet $dir
if ($Password) {
    Set-WfPassword $dir (ToPlain $Password) 'setup.ps1'
    Write-Host 'Server password saved.'
} elseif ($hasPassword) {
    if (AskYesNo 'A server password is already set. Change it?' $false) { $hasPassword = $false }
}
if (-not $Password -and -not $hasPassword) {
    if ($NoPrompt) { throw 'A server password is needed (-Password).' }
    Write-Host 'Choose a password that friends type to join. Use one you do not use anywhere else; it is stored in plain text in your server folder.'
    while ($true) {
        $p1 = ToPlain (Read-Host 'Server password' -AsSecureString)
        $p2 = ToPlain (Read-Host 'Type it again' -AsSecureString)
        if ($p1 -ne $p2) { Write-Warning 'The two did not match. Try again.'; continue }
        try { Set-WfPassword $dir $p1 'setup.ps1'; break } catch { Write-Warning $_.Exception.Message }
    }
    Write-Host 'Server password saved.'
}

# Admin
Write-Host ''
Write-Host 'Admins can kick and ban players from the server console. Your Steam ID is a 17-digit number starting 7656119.'
Write-Host 'Find it: Steam > your name > View my profile; if the address looks like steamcommunity.com/profiles/76561198..., that number is it.'
Write-Host 'If it shows /id/yourname instead, look yourself up at steamid.io and copy "steamID64".'
$adminDone = $false
while (-not $adminDone) {
    $a = if ($AdminSteamId) { $AdminSteamId } else { Ask 'Your Steam ID or profile link (Enter to skip)' '' }
    if (-not $a) { Write-Host 'No admin added. You can add one later: put the ID in instances\' -NoNewline; Write-Host "$Instance\admins.local"; break }
    try {
        $id = Add-WfAdmin $dir $a
        Write-Host "Admin added: $id"
        if (Test-Path (Join-Path $dir 'server_privilege.sprv')) {
            Write-Host "Note: this server has already started once, so its roles file exists. Give yourself admin in the server console with:  role $id,admin"
        }
        $adminDone = $true
    } catch {
        Write-Warning $_.Exception.Message
        $AdminSteamId = ''
        if ($NoPrompt) { throw }
    }
}

Step '4 of 6: your server files'
Write-Host "Your settings live in instances\$Instance. Updating this app never changes that folder."

# ---- 5. Firewall -------------------------------------------------------------------------------------------------------
Step '5 of 6: Windows Firewall'
$port = Get-WfGamePort $dir
if ($SkipFirewall) {
    Write-Host 'Skipped (-SkipFirewall).'
} elseif (Test-WfFirewallRule $port) {
    Write-Host "UDP $port is already open in Windows Firewall."
} else {
    Write-Host "Windows Firewall has to allow incoming UDP $port. Windows will now ask for permission (a blue/yellow shield window): click Yes."
    try {
        $null = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'firewall.ps1') + '"'), '-Ports', "$port")
    } catch { Write-Warning "The permission prompt was cancelled or failed ($($_.Exception.Message))." }
    if (Test-WfFirewallRule $port) { Write-Host "UDP $port is now open." }
    else {
        Write-Warning "UDP $port is still not open. Friends will not be able to join until it is."
        Write-Host "Fix it later: open PowerShell as Administrator in this folder and run   .\scripts\firewall.ps1 -Ports $port"
    }
}

# ---- 6. Router ---------------------------------------------------------------------------------------------------------
Step '6 of 6: your router (this one step cannot be automated)'
$net = Get-WfLocalNetwork
Write-Host 'For friends outside your home to join, your router must send the game''s traffic to this PC:'
Write-Host ''
Write-Host "  1. Set a static IP address for this PC in the router (called a DHCP reservation or static lease)."
Write-Host "       This PC's address now: $(if ($net.ip) { $net.ip } else { '(could not be read)' })$(if ($net.adapter) { '  on ' + $net.adapter })"
Write-Host "  2. Forward  UDP  port  $port  (external and internal) to that address (port forwarding / virtual server)."
Write-Host ''
if ($net.gateway) { Write-Host "  Your router's web page is probably   http://$($net.gateway)   (some routers, such as Deco or eero, have only a phone app instead)." }
Write-Host '  Every router looks different: search for your router model plus "port forwarding".'
Write-Host '  Once the server runs, the settings page''s Network tab tells you whether the forward worked.'
Write-Host '  Playing on your own home network needs none of this.'
Write-Host ''
Write-Host 'Setup finished.' -ForegroundColor Green
exit 0
