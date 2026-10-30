# Shared settings logic. Dot-source: . "$PSScriptRoot\settings.ps1"
#
# instances/<name>/settings.json (tracked) holds OVERRIDES: a field that is present replaces that value in
# every event of the loop (rules/bot count/ai set) or in the server config. A field that is absent leaves
# the template untouched. Used by start.ps1 (to generate files) and ui.ps1 (to edit them).
#
# Templates stay the source of truth, the generated files are gitignored:
#   default_loop.template.becl -> default_loop.becl
#   server_config.template.scnf (+ password.local) -> server_config.scnf

# Every field the UI can set. Section = where the value lives in the config.
#   event-rule : events[].rules[0][key]      event : events[][key]      event-ai : events[].level[0][key]
#   server     : 'game server config'[0][key]  net : 'net server config'[0][key]
# Rule flags the page offers (each tested on a local server: the server accepted and echoed it). In a rules block they go in
# one string, lower case, separated by "|". The server silently DROPS the whole string if the separator is wrong (comma,
# semicolon, plain space) and silently ignores names it does not know. More names exist in the game (disable special vehicles,
# disable class a..d) but were not tested. See docs/game-data-sources.md.
$WfRuleFlags = @('disable car resets', 'disable tuning', 'disable upgrades', 'disable wrong way limiter')

$WfFields = @(
    [pscustomobject]@{ Key = 'bot count';                 Section = 'event';      Type = 'int';    Min = 0; Max = 24;      Label = 'Bots';                   Hint = 'AI cars added to every event' }
    [pscustomobject]@{ Key = 'ai set path';                Section = 'event-ai';   Type = 'string';                         Label = 'AI set';                 Hint = 'Which AI set (skill / car class) the bots use, e.g. career/ai-class-all.aist' }
    [pscustomobject]@{ Key = 'vehicle damage id';          Section = 'event-rule'; Type = 'string';                         Label = 'Damage preset';          Hint = 'Vehicle damage preset. Game default leaves it to the game' }
    [pscustomobject]@{ Key = 'laps';                       Section = 'event-rule'; Type = 'int';    Min = 1; Max = 99;      Label = 'Laps';                   Hint = '' }
    [pscustomobject]@{ Key = 'time limit';                 Section = 'event-rule'; Type = 'int';    Min = 1; Max = 600;     Label = 'Time limit (minutes)';   Hint = '' }
    [pscustomobject]@{ Key = 'max number of participants'; Section = 'event-rule'; Type = 'int';    Min = 1; Max = 24;      Label = 'Max players';            Hint = 'Players plus bots' }
    [pscustomobject]@{ Key = 'car reset delay (seconds)';  Section = 'event-rule'; Type = 'int';    Min = 0; Max = 60;      Label = 'Car reset delay (s)';    Hint = '' }
    [pscustomobject]@{ Key = 'flags';                      Section = 'event-rule'; Type = 'string';                         Label = 'Rule flags';             Hint = 'Switch off car resets, tuning, upgrades or the wrong-way limiter' }
    [pscustomobject]@{ Key = 'name';                       Section = 'net';        Type = 'string';                         Label = 'Server name';            Hint = 'Shown in the server browser' }
    [pscustomobject]@{ Key = 'description';                Section = 'net';        Type = 'string';                         Label = 'Description';            Hint = '' }
    [pscustomobject]@{ Key = 'countdown time';             Section = 'server';     Type = 'int';    Min = 0; Max = 600000;  Label = 'Countdown (ms)';         Hint = 'Time before a race starts' }
    [pscustomobject]@{ Key = 'voting time';                Section = 'server';     Type = 'int';    Min = 0; Max = 600000;  Label = 'Voting time (ms)';       Hint = 'Time players have to vote on the next event' }
)

function Get-WfInstanceDir([string]$Root, [string]$Instance) {
    if ($Instance -notmatch '^[A-Za-z0-9_-]+$') { throw "Bad instance name '$Instance'." }
    Join-Path $Root "instances\$Instance"
}

# Returns an ordered hashtable of the saved overrides (empty when none).
function Read-WfOverrides([string]$InstanceDir) {
    $out = [ordered]@{}
    $file = Join-Path $InstanceDir 'settings.json'
    if (-not (Test-Path $file)) { return $out }
    $json = Read-WfJson $file
    if (-not $json.overrides) { return $out }
    foreach ($f in $WfFields) {
        $p = $json.overrides.PSObject.Properties[$f.Key]
        if ($p) { $out[$f.Key] = $p.Value }
    }
    if ($out.Contains('ai set path')) { $out['ai set path'] = ConvertTo-WfAiSetPath $out['ai set path'] }   # old short form -> full path
    $out
}

# Validates $Overrides (hashtable or PSCustomObject) against $WfFields and returns a clean ordered hashtable.
# Unknown keys are dropped, bad values throw.
function ConvertTo-WfOverrides($Overrides) {
    $out = [ordered]@{}
    foreach ($f in $WfFields) {
        $p = $Overrides.PSObject.Properties[$f.Key]
        $has = if ($Overrides -is [System.Collections.IDictionary]) { $Overrides.Contains($f.Key) } else { [bool]$p }
        if (-not $has) { continue }
        $v = if ($Overrides -is [System.Collections.IDictionary]) { $Overrides[$f.Key] } else { $p.Value }
        if ($f.Type -eq 'int') {
            $n = 0
            if ($v -is [bool] -or -not [int]::TryParse([string]$v, [ref]$n)) { throw "$($f.Label) must be a whole number." }
            if ($n -lt $f.Min -or $n -gt $f.Max) { throw "$($f.Label) must be between $($f.Min) and $($f.Max)." }
            $out[$f.Key] = $n
        } else {
            if ($v -isnot [string]) { throw "$($f.Label) must be text." }
            if ($v.Length -gt 200 -or $v -match '[\x00-\x1f]') { throw "$($f.Label) is too long or has control characters." }
            if ($f.Key -eq 'ai set path') {
                $v = ConvertTo-WfAiSetPath $v
                if ($v -ne '' -and -not (Test-WfAiSetPath $v)) { throw "AI set '$v' is not a path the server accepts." }
            }
            if ($f.Key -eq 'flags') {
                # Only names the server is known to accept, joined the way it expects. Anything else would be silently dropped.
                $names = @($v -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $bad = @($names | Where-Object { $WfRuleFlags -notcontains $_ })
                if ($bad.Count) { throw "Unknown rule flag '$($bad[0])'. Use: $($WfRuleFlags -join ', ')." }
                $v = (@($WfRuleFlags | Where-Object { $names -contains $_ })) -join ' | '
            }
            $out[$f.Key] = $v
        }
    }
    $out
}

function Write-WfOverrides([string]$InstanceDir, $Overrides) {
    $clean = ConvertTo-WfOverrides $Overrides
    Write-WfJson (Join-Path $InstanceDir 'settings.json') ([ordered]@{ overrides = $clean })
    $clean
}

# Applies DEFAULTS to the parsed loop (modifies in place). Returns the number of events.
# $Overrides is the merged default for these events: the Global defaults, with a cup's own settings laid over them for a cup.
# An event that lists a field in its own "overrides" array keeps its own value for that field and is skipped for it, so the
# order of precedence is: the event's own value, then the cup, then Global, then whatever the event file says.
function Set-WfLoopOverrides($Loop, $Overrides) {
    foreach ($ev in $Loop.events) {
        $own = @($ev.overrides)
        foreach ($f in $WfFields) {
            if (-not $Overrides.Contains($f.Key)) { continue }
            if ($own -contains $f.Key) { continue }
            switch ($f.Section) {
                'event'      { $ev.($f.Key) = $Overrides[$f.Key] }
                'event-ai'   { foreach ($l in $ev.level) { $l.($f.Key) = $Overrides[$f.Key] } }
                'event-rule' { foreach ($r in $ev.rules) { $r.($f.Key) = $Overrides[$f.Key] } }
            }
        }
    }
    @($Loop.events).Count
}

function Set-WfServerOverrides($Config, $Overrides) {
    foreach ($f in $WfFields) {
        if (-not $Overrides.Contains($f.Key)) { continue }
        switch ($f.Section) {
            'net'    { $Config.'net server config'[0].($f.Key) = $Overrides[$f.Key] }
            'server' { $Config.'game server config'[0].($f.Key) = $Overrides[$f.Key] }
        }
    }
}

# Windows PowerShell 5.1's Get-Content reads UTF-8 as ANSI and garbles characters like the apostrophe in cup text.
function Read-WfJson([string]$Path) { [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding $false)) | ConvertFrom-Json }

# Pretty JSON in the same style as the game's own files (4-space indent, "key": value, LF). Windows PowerShell 5.1's
# ConvertTo-Json indents oddly and escapes apostrophes, which would make every tracked config diff noisy.
function ConvertTo-WfJsonString([string]$s) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default { if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
        }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function ConvertTo-WfPrettyJson($Value, [int]$Level = 0) {
    $pad  = '    ' * $Level
    $pad1 = '    ' * ($Level + 1)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return ConvertTo-WfJsonString $Value }
    if ($Value -is [int] -or $Value -is [long]) { return ([long]$Value).ToString([Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) { return ([double]$Value).ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = @($Value.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $Value[$_] } })
    } elseif ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $parts = $items | ForEach-Object { $pad1 + (ConvertTo-WfPrettyJson $_ ($Level + 1)) }
        return "[`n" + ($parts -join ",`n") + "`n$pad]"
    } else {
        $pairs = @($Value.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
    }
    if ($pairs.Count -eq 0) { return '{}' }
    $parts = $pairs | ForEach-Object { $pad1 + (ConvertTo-WfJsonString $_.Name) + ': ' + (ConvertTo-WfPrettyJson $_.Value ($Level + 1)) }
    "{`n" + ($parts -join ",`n") + "`n$pad}"
}

function Write-WfJson([string]$Path, $Object) {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($Path, (ConvertTo-WfPrettyJson $Object), (New-Object Text.UTF8Encoding $false))
}

# Server password: password.local (gitignored), same format set-password.ps1 writes. The page only gets it back when
# Show is clicked (Get-WfPassword); it is not part of /api/state. An empty password (open server) can't be set here; do
# that by editing the file.
function Get-WfPassword([string]$InstanceDir) {
    $f = Join-Path $InstanceDir 'password.local'
    if (Test-Path $f) { [IO.File]::ReadAllText($f).Trim() } else { '' }
}
function Test-WfPasswordSet([string]$InstanceDir) {
    $f = Join-Path $InstanceDir 'password.local'
    (Test-Path $f) -and ([IO.File]::ReadAllText($f).Trim() -ne '')
}
function Set-WfPassword([string]$InstanceDir, $Password, [string]$By = 'settings page') {
    if ($Password -isnot [string]) { throw 'Password must be text.' }
    $p = $Password.Trim()
    if ($p -eq '') { throw "Password can't be empty." }
    if ($p.Length -gt 64) { throw 'Password is too long (max 64 characters).' }
    if ($p -match '[\x00-\x1f]') { throw 'Password has control characters.' }
    [IO.File]::WriteAllText((Join-Path $InstanceDir 'password.local'), $p, (New-Object Text.UTF8Encoding $false))
    Add-WfPasswordHistory $InstanceDir $By
}

. "$PSScriptRoot\loops.ps1"   # per-event loops and cups
. "$PSScriptRoot\apply.ps1"   # push saved settings to a running server
. "$PSScriptRoot\server.ps1"  # start and stop a server instance
. "$PSScriptRoot\instance.ps1" # create an instance from defaults\instance, Steam name, admins
. "$PSScriptRoot\network.ps1"  # port forwarding help and the installed game build
. "$PSScriptRoot\appupdate.ps1" # this app's own version and self-update
. "$PSScriptRoot\remote.ps1"    # remote control over Tailscale: password, sessions, activity log

# Generates default_loop.becl from its template plus the overrides. No-op when there is no template.
function Build-WfLoop([string]$InstanceDir) {
    $template = Join-Path $InstanceDir 'default_loop.template.becl'
    if (-not (Test-Path $template)) { return }
    $loop = Read-WfJson $template
    Repair-WfLoopAiSets $loop                  # AI sets saved in the old short form become the full path the server accepts
    $loop.events = Get-WfEnabledEvents $loop   # events switched off on the page are left out of what the game reads
    $null = Set-WfLoopOverrides $loop (Read-WfOverrides $InstanceDir)
    Clear-WfEventMarkers $loop                 # the page's bookkeeping is not part of the game's file
    Write-WfJson (Join-Path $InstanceDir 'default_loop.becl') $loop
}

# Removes the keys only the settings page uses ("overrides") from every event, before a file is written for the game.
function Clear-WfEventMarkers($Loop) {
    foreach ($ev in @($Loop.events)) { $ev.PSObject.Properties.Remove('overrides') }
}
