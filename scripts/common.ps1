# Shared paths. Dot-source from other scripts: . "$PSScriptRoot\common.ps1"
$Root     = Split-Path $PSScriptRoot -Parent
$SteamCmd = Join-Path $Root 'steamcmd'
$Server   = Join-Path $Root 'server'
$AppId    = 3519390   # Wreckfest 2 Dedicated Server

# Password change history: instances\<name>\password-history.local (gitignored). It records when and how the password was
# changed, never the password itself.
function Get-WfPasswordHistoryRaw([string]$InstanceDir) {
    $f = Join-Path $InstanceDir 'password-history.local'
    $list = New-Object 'Collections.Generic.List[object]'
    if (Test-Path $f) {
        try { $parsed = [IO.File]::ReadAllText($f) | ConvertFrom-Json; foreach ($e in $parsed) { if ($e.at) { $at = if ($e.at -is [DateTime]) { $e.at.ToUniversalTime().ToString('o') } else { [string]$e.at }; $list.Add([pscustomobject]@{ at = $at; by = [string]$e.by }) } } } catch { }   # 5.1 turns ISO strings into DateTime
    }
    , $list
}

function Add-WfPasswordHistory([string]$InstanceDir, [string]$By) {
    $list = Get-WfPasswordHistoryRaw $InstanceDir
    $list.Add([pscustomobject]@{ at = [DateTime]::UtcNow.ToString('o'); by = $By })
    while ($list.Count -gt 200) { $list.RemoveAt(0) }
    $f = Join-Path $InstanceDir 'password-history.local'
    [IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $list.ToArray() -Depth 3), (New-Object Text.UTF8Encoding $false))
}

# Newest first. When no history was kept yet but a password exists, its file date stands in as the one known change.
function Read-WfPasswordHistory([string]$InstanceDir) {
    $entries = @((Get-WfPasswordHistoryRaw $InstanceDir).ToArray())
    if ($entries.Count -eq 0) {
        $pw = Join-Path $InstanceDir 'password.local'
        if (Test-Path $pw) { $entries = @([pscustomobject]@{ at = (Get-Item $pw).LastWriteTimeUtc.ToString('o'); by = 'before history was kept (file date)' }) }
    }
    @($entries | Sort-Object { [DateTime]::Parse($_.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } -Descending)
}
