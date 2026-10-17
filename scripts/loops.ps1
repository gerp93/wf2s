# Per-event loops and cups, edited by the settings page. Dot-sourced by settings.ps1 (needs its helpers).
#
# Loop ids: 'main' = default_loop.template.becl; 'cup:<slug>' = cups\<slug>.becl. A custom cup loop is copied into
# the game's cup folder at start as wf2s_<slug>.becl (the game's own cup loops are binary files we cannot edit).
$WfCupLoopDir = 'data/property/settings/cup'

function Get-WfLoopFile([string]$InstanceDir, [string]$Id) {
    if ($Id -eq 'main') { return Join-Path $InstanceDir 'default_loop.template.becl' }
    if ($Id -match '^cup:([a-z0-9_]{1,40})$') { return Join-Path $InstanceDir "cups\$($Matches[1]).becl" }
    throw "Unknown loop '$Id'."
}

function Assert-WfText($v, [string]$What, [int]$Max = 300, [switch]$Required) {
    if ($v -isnot [string]) { throw "$What must be text." }
    if ($v.Length -gt $Max -or $v -match '[\x00-\x1f]') { throw "$What is too long or has control characters." }
    if ($Required -and $v.Trim() -eq '') { throw "$What can't be empty." }
}
function Assert-WfNumber($v, [string]$What, [double]$Min, [double]$Max, [switch]$Whole) {
    $n = 0.0
    $inv = [Globalization.CultureInfo]::InvariantCulture
    if ($v -is [bool] -or $null -eq $v -or -not [double]::TryParse([string]::Format($inv, '{0}', $v), [Globalization.NumberStyles]::Float, $inv, [ref]$n)) { throw "$What must be a number." }
    if ($Whole -and $n -ne [math]::Floor($n)) { throw "$What must be a whole number." }
    if ($n -lt $Min -or $n -gt $Max) { throw "$What must be between $Min and $Max." }
}
function Assert-WfCarRestriction($list, [string]$What) {
    if ($null -eq $list) { return }
    $items = @($list)
    if ($items.Count -gt 100) { throw "$What has too many entries." }
    foreach ($c in $items) {
        Assert-WfText $c.'allowed car type' "$What car type" 60 -Required
        Assert-WfText $c.flags "$What flags" 60
    }
}

# AI set paths the server accepts (tested on a local server): the built-in class sets career/ai-class-all|a|b|c|d.aist, and a FULL
# file path data/property/career/ai_sets/<...>.aist. The short form career/ai_sets/<...> (which earlier versions of this page
# wrote) is rejected ("Invalid AI set path"), so it is rewritten to the full form wherever it is read. See docs/game-data-sources.md.
$WfAiClassSets = @('career/ai-class-all.aist', 'career/ai-class-a.aist', 'career/ai-class-b.aist', 'career/ai-class-c.aist', 'career/ai-class-d.aist')
function ConvertTo-WfAiSetPath($Path) {
    if ($Path -is [string] -and $Path -like 'career/ai_sets/*') { return 'data/property/' + $Path }
    $Path
}
function Test-WfAiSetPath([string]$Path) { ($WfAiClassSets -contains $Path) -or ($Path -match '^data/property/career/ai_sets/[A-Za-z0-9_/\.\-]+\.aist$') }
function Repair-WfLoopAiSets($Loop) {
    foreach ($ev in @($Loop.events)) { foreach ($l in @($ev.level)) { if ($l.PSObject.Properties['ai set path']) { $l.'ai set path' = ConvertTo-WfAiSetPath $l.'ai set path' } } }
}

# An event can be switched off on the page: its entry in the template/cup file carries "disabled": true and is left out
# when the files the game reads are generated. The game never sees the key.
function Get-WfEnabledEvents($Loop) {
    $enabled = @($Loop.events | Where-Object { $_.disabled -ne $true })
    foreach ($ev in $enabled) { $ev.PSObject.Properties.Remove('disabled') }
    $enabled
}

# Validates a parsed loop. Unknown keys are kept (the game may add some); known keys are checked.
function Assert-WfLoop($Loop) {
    $events = @($Loop.events)
    if ($events.Count -lt 1) { throw 'A loop needs at least one event.' }
    if ($events.Count -gt 500) { throw 'Too many events (max 500).' }
    if (@($events | Where-Object { $_.disabled -ne $true }).Count -lt 1) { throw 'At least one event has to stay enabled.' }
    $n = 0
    foreach ($ev in $events) {
        $n++; $w = "Event $n"
        if ($null -ne $ev.disabled -and $ev.disabled -isnot [bool]) { throw "$w disabled flag must be true or false." }
        # "overrides": the fields this event sets itself instead of following the cup or Global default (see Set-WfLoopOverrides).
        if ($null -ne $ev.overrides) { foreach ($k in @($ev.overrides)) {
            if ($k -isnot [string] -or @($WfFields | Where-Object { $_.Key -eq $k -and $_.Section -in 'event', 'event-ai', 'event-rule' }).Count -eq 0) {
                throw "$w has an unknown field in its list of overrides: '$k'."
            }
        } }
        if (@($ev.level).Count -ne 1 -or @($ev.rules).Count -ne 1) { throw "$w needs one level and one rules block." }
        $l = @($ev.level)[0]; $r = @($ev.rules)[0]
        Assert-WfText $l.'level id' "$w track" 80 -Required
        Assert-WfText $l.'game mode id' "$w game mode" 80 -Required
        Assert-WfText $l.'weather path' "$w weather" 200
        Assert-WfText $l.'weather intent path' "$w weather intent" 200
        Assert-WfText $l.'ai set path' "$w AI set" 200
        if ($l.'ai set path' -ne '' -and -not (Test-WfAiSetPath $l.'ai set path')) { throw "$w AI set '$($l.'ai set path')' is not a path the server accepts." }
        Assert-WfNumber $r.laps "$w laps" 0 99 -Whole
        Assert-WfNumber $r.'time limit' "$w time limit" 0 600 -Whole
        Assert-WfNumber $r.'number of teams' "$w teams" 1 24 -Whole
        Assert-WfNumber $r.'max number of participants' "$w max players" 1 24 -Whole
        Assert-WfText $r.flags "$w flags" 100
        Assert-WfText $r.'collecting order' "$w collecting order" 60
        Assert-WfNumber $r.'car reset delay (seconds)' "$w car reset delay" 0 60 -Whole
        Assert-WfText $r.'vehicle damage id' "$w damage preset" 80
        Assert-WfNumber $ev.'bot count' "$w bots" 0 24 -Whole
        Assert-WfCarRestriction $ev.'car restriction' "$w car restriction"
    }
}

function Read-WfLoop([string]$InstanceDir, [string]$Id) {
    $file = Get-WfLoopFile $InstanceDir $Id
    if (-not (Test-Path $file)) { throw "No loop file for '$Id'." }
    $loop = Read-WfJson $file
    Repair-WfLoopAiSets $loop
    $loop
}

function Save-WfLoop([string]$InstanceDir, [string]$Id, $Loop) {
    Assert-WfLoop $Loop
    Write-WfJson (Get-WfLoopFile $InstanceDir $Id) ([ordered]@{ events = @($Loop.events) })
}

function ConvertTo-WfSlug([string]$Name) {
    $s = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
    if ($s.Length -gt 30) { $s = $s.Substring(0, 30).Trim('_') }
    if ($s -eq '') { $s = 'cup' }
    $s
}

# The events in one of the game's own cup loops, in order (a track can appear more than once), as @{ id; laps; minutes }.
# Those files are binary: each event is an 'lvlm' block holding the track id, then an 'urve' block whose first values are
# [version, 1, laps, time limit in minutes, ...]. 666 as a time limit means "none" (the waypoint races). Mode and weather
# are not stored; the game uses each track's own defaults for those.
function Get-WfBuiltinCupEvents([string]$ServerDir, [string]$LoopPath) {
    if ($LoopPath -notmatch '^data/property/settings/cup/[a-z0-9_]+\.becl$') { return @() }
    $file = Join-Path $ServerDir ($LoopPath.Replace('/', [string][IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path $file)) { return @() }
    try {
        Initialize-WfGameText
        $text = [WfGameText]::Text($file)
        if (-not $text) { return @() }
        $latin = [Text.Encoding]::GetEncoding(28591)
        $found = foreach ($chunk in (($text -split 'lvlm') | Select-Object -Skip 1)) {
            if ($chunk -notmatch '(track\d+(?:_[a-z0-9]+)*)') { continue }
            $ev = @{ id = $Matches[1]; laps = $null; minutes = $null }
            $at = $chunk.IndexOf('urve')
            if ($at -ge 0) {
                $bytes = $latin.GetBytes($chunk)
                if ($at + 20 -le $bytes.Length) {
                    $ev.laps = [BitConverter]::ToInt32($bytes, $at + 12)
                    $m = [BitConverter]::ToInt32($bytes, $at + 16)
                    if ($m -gt 0 -and $m -le 600) { $ev.minutes = $m }
                }
            }
            $ev
        }
        @($found)
    } catch { @() }
}

# Creates cups\<slug>.becl and returns the cup's 'event loop' path for it. With -From (one of the game's own cup loops) it
# starts with that cup's events: the track, laps and time limit the game uses, the track's default mode, and everything
# else (weather, bots, ...) from the main rotation's event for that track. Otherwise it is a copy of the main rotation.
function New-WfCupLoop([string]$InstanceDir, [string]$Name, [string]$ServerDir, [string]$From) {
    $base = ConvertTo-WfSlug $Name
    $slug = $base; $i = 2
    while (Test-Path (Get-WfLoopFile $InstanceDir "cup:$slug")) { $slug = "${base}_$i"; $i++ }
    Save-WfLoop $InstanceDir "cup:$slug" (Get-WfSeedLoop $InstanceDir $ServerDir $From)
    "$WfCupLoopDir/wf2s_$slug.becl"
}

# Clones a custom cup's own events file under a new name (every event, switched-on state and per-event overrides included)
# and returns the new cup's 'event loop' path. Cloning a built-in cup uses New-WfCupLoop -From instead.
function Copy-WfCupLoop([string]$InstanceDir, [string]$Name, [string]$FromSlug) {
    if ($FromSlug -notmatch '^[a-z0-9_]{1,40}$') { throw 'Bad cup events id.' }
    $loop = Read-WfLoop $InstanceDir "cup:$FromSlug"
    $base = ConvertTo-WfSlug $Name
    $slug = $base; $i = 2
    while (Test-Path (Get-WfLoopFile $InstanceDir "cup:$slug")) { $slug = "${base}_$i"; $i++ }
    Save-WfLoop $InstanceDir "cup:$slug" $loop
    "$WfCupLoopDir/wf2s_$slug.becl"
}

# The starting events for a cup's own loop: see New-WfCupLoop.
function Get-WfSeedLoop([string]$InstanceDir, [string]$ServerDir, [string]$From) {
    $loop = Read-WfLoop $InstanceDir 'main'
    $cupEvents = if ($From -and $ServerDir) { @(Get-WfBuiltinCupEvents $ServerDir $From) } else { @() }
    if ($cupEvents.Count -gt 0) {
        $modes = Get-WfTrackModes $ServerDir
        $clone = { param($x) $x | ConvertTo-Json -Depth 20 | ConvertFrom-Json }
        $events = foreach ($ce in $cupEvents) {
            $src = @($loop.events | Where-Object { @($_.level)[0].'level id' -eq $ce.id })[0]
            $ev = & $clone $(if ($src) { $src } else { @($loop.events)[0] })
            $l = @($ev.level)[0]; $r = @($ev.rules)[0]
            $l.'level id' = $ce.id
            if ($modes.Contains($ce.id)) { $l.'game mode id' = $modes[$ce.id] }
            if ($null -ne $ce.laps) { $r.laps = $ce.laps }
            if ($null -ne $ce.minutes) { $r.'time limit' = $ce.minutes }
            $ev.PSObject.Properties.Remove('disabled')
            $ev
        }
        $loop = [pscustomobject]@{ events = @($events) }
    }
    $loop
}

# The cup list the PAGE edits. The file the game reads (server_cup_config.ccnl) is generated from it at every start, because a
# custom cup's events path has to point into the instance folder (see Publish-WfCupLoops). Older instances kept the editable
# list under the game's own name; it is copied to the template once.
function Get-WfCupsFile([string]$InstanceDir) {
    $template = Join-Path $InstanceDir 'server_cup_config.template.ccnl'
    $legacy   = Join-Path $InstanceDir 'server_cup_config.ccnl'
    if (-not (Test-Path $template) -and (Test-Path $legacy)) { Copy-Item $legacy $template }
    $template
}

# The game's own cups as shipped, kept in defaults\ so "Reset to defaults" has something to go back to. A built-in cup is
# identified by the 'event loop' path it started with (e.g. data/property/settings/cup/clown_show.becl).
function Get-WfDefaultCups {
    $file = Join-Path $PSScriptRoot '..\defaults\server_cup_config.ccnl'
    $map = [ordered]@{}
    if (Test-Path $file) { foreach ($c in (Read-WfJson $file).cups) { $map[[string]$c.'event loop'] = $c } }
    $map
}

# Extra per-cup data lives in cups\builtin.json, beside the cups and not in the game's cup file, which the game parses.
# One entry per cup, in order:
#   builtin   - the shipped cup it started as (null = a cup you made). Without the file (first run) a cup counts as
#               built-in when its event loop or its name matches a shipped one.
#   overrides - cup-level settings that replace the same setting in every event of that cup when the cup is published
#               ('bot count', 'vehicle damage id', 'ai set path'); a key that is absent is not overridden. The cup's own events file keeps
#               each event's own value, so switching an override off brings those back.
$WfCupOverrideKeys = @('bot count', 'vehicle damage id', 'ai set path')
function Get-WfBuiltinFile([string]$InstanceDir) { Join-Path $InstanceDir 'cups\builtin.json' }

function Read-WfCups([string]$InstanceDir) {
    $file = Get-WfCupsFile $InstanceDir
    if (-not (Test-Path $file)) { return [pscustomobject]@{ cups = @() } }
    $config = Read-WfJson $file
    $defaults = Get-WfDefaultCups
    $saved = $null; $savedOv = $null
    $bf = Get-WfBuiltinFile $InstanceDir
    if (Test-Path $bf) { $meta = Read-WfJson $bf; $saved = @($meta.builtin); $savedOv = @($meta.overrides) }
    $cups = @($config.cups)
    for ($i = 0; $i -lt $cups.Count; $i++) {
        $id = $null
        if ($null -ne $saved -and $saved.Count -eq $cups.Count) { $id = $saved[$i] }
        elseif ($null -eq $saved) {
            if ($defaults.Contains([string]$cups[$i].'event loop')) { $id = [string]$cups[$i].'event loop' }
            else { foreach ($k in $defaults.Keys) { if ($defaults[$k].'cup name' -eq $cups[$i].'cup name') { $id = $k; break } } }
        }
        if ($id -and -not $defaults.Contains([string]$id)) { $id = $null }
        $cups[$i] | Add-Member -NotePropertyName builtin -NotePropertyValue $id -Force
        $ov = if ($null -ne $savedOv -and $savedOv.Count -eq $cups.Count -and $null -ne $savedOv[$i]) { $savedOv[$i] } else { [pscustomobject]@{} }
        if ($ov.PSObject.Properties['ai set path']) { $ov.'ai set path' = ConvertTo-WfAiSetPath $ov.'ai set path' }   # old short form -> full path
        $cups[$i] | Add-Member -NotePropertyName overrides -NotePropertyValue $ov -Force
    }
    $config.cups = $cups
    $config
}

function Save-WfCups([string]$InstanceDir, $Config) {
    $cups = @($Config.cups)
    if ($cups.Count -gt 50) { throw 'Too many cups (max 50).' }
    $defaults = Get-WfDefaultCups
    $builtin = @(); $overrides = @()
    $n = 0
    foreach ($c in $cups) {
        $n++; $w = "Cup $n"
        $id = $c.builtin
        if ($null -ne $id -and ($id -isnot [string] -or -not $defaults.Contains($id))) { throw "$w is marked built-in but is not one of the game's cups." }
        $builtin += , $id
        $c.PSObject.Properties.Remove('builtin')
        $ov = [ordered]@{}
        if ($null -ne $c.overrides) {
            foreach ($p in $c.overrides.PSObject.Properties) {
                if ($WfCupOverrideKeys -notcontains $p.Name) { throw "$w has an unknown cup-level setting '$($p.Name)'." }
                if ($p.Name -eq 'bot count') { Assert-WfNumber $p.Value "$w bots" 0 24 -Whole; $ov[$p.Name] = [int]$p.Value }
                elseif ($p.Name -eq 'ai set path') {
                    $v = ConvertTo-WfAiSetPath ([string]$p.Value)
                    Assert-WfText $v "$w AI set" 200 -Required
                    if (-not (Test-WfAiSetPath $v)) { throw "$w AI set '$v' is not a path the server accepts." }
                    $ov[$p.Name] = $v
                }
                else { Assert-WfText $p.Value "$w damage preset" 80; $ov[$p.Name] = $p.Value }
            }
        }
        $overrides += , $ov
        $c.PSObject.Properties.Remove('overrides')
        Assert-WfText $c.'cup name' "$w name" 100 -Required
        Assert-WfText $c.'cup description' "$w description" 400
        Assert-WfText $c.icon "$w icon" 200
        Assert-WfText $c.'event loop' "$w event loop" 200 -Required
        if ($c.'event loop' -notmatch '^data/property/settings/cup/[A-Za-z0-9_.-]+\.becl$') { throw "$w event loop must be a .becl file in $WfCupLoopDir." }
        Assert-WfCarRestriction $c.'car restriction' "$w car restriction"
        if (@($c.'race settings').Count -ne 1) { throw "$w needs one race settings block." }
        $s = @($c.'race settings')[0]
        Assert-WfText $s.'point distribution' "$w point distribution" 200 -Required
        if ($s.'point distribution' -notmatch '^\d+(;\d+)*$') { throw "$w point distribution must be numbers separated by semicolons, e.g. 30;27;25." }
        Assert-WfText $s.flags "$w flags" 100
        Assert-WfText $s.'start order' "$w start order" 60 -Required
        Assert-WfNumber $s.'points for best lap time' "$w points for best lap" 0 1000 -Whole
        Assert-WfNumber $s.'points for highest score' "$w points for highest score" 0 1000 -Whole
        Assert-WfNumber $s.'last race multiplier' "$w last race multiplier" 0 100
    }
    Write-WfJson (Get-WfCupsFile $InstanceDir) ([ordered]@{ cups = $cups })
    $bf = Get-WfBuiltinFile $InstanceDir
    New-Item -ItemType Directory -Force (Split-Path $bf) | Out-Null
    Write-WfJson $bf ([ordered]@{ builtin = @($builtin); overrides = @($overrides) })
    # A cup's own events (cups\<slug>.becl) are dropped once no cup uses them, e.g. after a reset or a delete.
    $used = @($cups | ForEach-Object { if ($_.'event loop' -match '/wf2s_([a-z0-9_]{1,40})\.becl$') { $Matches[1] } })
    foreach ($f in Get-ChildItem (Join-Path $InstanceDir 'cups') -Filter '*.becl' -ErrorAction SilentlyContinue) {
        if ($f.BaseName -match '^[a-z0-9_]{1,40}$' -and $used -notcontains $f.BaseName) { Remove-Item $f.FullName -Force }
    }
}

# Generates what the game reads for cups, into the instance (save) folder, like default_loop.becl is generated:
#   cups-generated\<slug>.becl       each custom cup's events (switched-off events dropped, Global/cup defaults applied)
#   server_cup_config.ccnl           the cup list, from server_cup_config.template.ccnl (the file the page edits). A custom
#                                    cup's placeholder path data/property/settings/cup/wf2s_<slug>.becl becomes
#                                    cups-generated/<slug>.becl, relative to the save folder.
# These must NOT go in the game's own data folder: (tested) the server rejects a loose file there ("has no valid events"),
# and every file that is not in the client's data makes the data checksum differ, so clients are refused to join
# ("Server checksum mismatch"). A JSON events file in the save folder is accepted and the cup runs (tested).
# Called by start.ps1 before launch and by Apply now.
function Publish-WfCupLoops([string]$InstanceDir, [string]$ServerDir) {
    $dest = Join-Path $InstanceDir 'cups-generated'
    New-Item -ItemType Directory -Force $dest | Out-Null
    $src = Join-Path $InstanceDir 'cups'
    $want = @()
    $globalDefaults = Read-WfOverrides $InstanceDir   # the Global defaults (settings.json); cups follow them too
    # cup-level settings, by the slug of the cup's own events file
    $cupOv = @{}
    $cupsRead = Read-WfCups $InstanceDir
    foreach ($c in @($cupsRead.cups)) {
        if ($c.'event loop' -match '/wf2s_([a-z0-9_]{1,40})\.becl$') { $cupOv[$Matches[1]] = $c.overrides }
    }
    if (Test-Path $src) {
        foreach ($f in Get-ChildItem $src -Filter '*.becl') {
            if ($f.BaseName -notmatch '^[a-z0-9_]{1,40}$') { continue }
            $loop = Read-WfJson $f.FullName
            Repair-WfLoopAiSets $loop
            $events = @(Get-WfEnabledEvents $loop)
            # Defaults for this cup's events: the Global defaults, with this cup's own settings laid over them. An event that
            # sets a field itself (its "overrides" list) keeps that value; see Set-WfLoopOverrides.
            $defaults = [ordered]@{}
            foreach ($k in $globalDefaults.Keys) { $defaults[$k] = $globalDefaults[$k] }
            $ov = $cupOv[$f.BaseName]
            if ($ov) {
                foreach ($p in $ov.PSObject.Properties) {
                    $defaults[$p.Name] = if ($p.Name -eq 'bot count') { [int]$p.Value } elseif ($p.Name -eq 'ai set path') { ConvertTo-WfAiSetPath ([string]$p.Value) } else { [string]$p.Value }
                }
            }
            $shell = [pscustomobject]@{ events = $events }
            $null = Set-WfLoopOverrides $shell $defaults
            Clear-WfEventMarkers $shell
            Write-WfJson (Join-Path $dest $f.Name) ([ordered]@{ events = $events })
            $want += $f.Name
        }
    }
    foreach ($old in Get-ChildItem $dest -Filter '*.becl') {
        if ($want -notcontains $old.Name) { Remove-Item $old.FullName -Force }
    }

    # The cup list the game reads.
    $template = Get-WfCupsFile $InstanceDir
    if (Test-Path $template) {
        $config = Read-WfJson $template
        $meta = @($cupsRead.cups)
        $keep = @(); $i = -1
        foreach ($c in @($config.cups)) {
            $i++
            if ($c.'event loop' -match '/wf2s_([a-z0-9_]{1,40})\.becl$') {
                $slug = $Matches[1]
                if ($want -contains "$slug.becl") { $c.'event loop' = "cups-generated/$slug.becl" }
                elseif ($i -lt $meta.Count -and $meta[$i].builtin) { $c.'event loop' = [string]$meta[$i].builtin }   # events file is gone: the game's own cup
                else { Write-Warning "Cup '$($c.'cup name')' has no events file and is left out."; continue }
            }
            $keep += $c
        }
        $config.cups = $keep
        Write-WfJson (Join-Path $InstanceDir 'server_cup_config.ccnl') $config
    }

    # Clean up after the old approach, which copied wf2s_<slug>.becl into the game's own data folder (see above).
    if ($ServerDir) {
        $old = Join-Path $ServerDir 'data\property\settings\cup'
        if (Test-Path $old) { Get-ChildItem $old -Filter 'wf2s_*.becl' | Remove-Item -Force }
    }
}

# ---- friendly names, read from the installed game's own files --------------------------------------------------------
# Event (.evse), environment (.envi) and weather (.weat) files are a 20-byte header followed by an LZ4 block and hold a
# localisation key followed by a length-prefixed English text, e.g. EVENT_TITLE_0657108540_12 -> "Main Circuit".
function Initialize-WfGameText {
    if ('WfGameText' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
public static class WfGameText {
    static byte[] Lz4(byte[] src, int start) {
        var o = new List<byte>(src.Length * 3); int i = start;
        while (i < src.Length) {
            int tok = src[i++]; int ll = tok >> 4;
            if (ll == 15) { int x; do { x = src[i++]; ll += x; } while (x == 255); }
            for (int k = 0; k < ll; k++) o.Add(src[i++]);
            if (i >= src.Length) break;
            int off = src[i] | (src[i + 1] << 8); i += 2;
            int ml = tok & 15;
            if (ml == 15) { int x; do { x = src[i++]; ml += x; } while (x == 255); }
            ml += 4;
            if (off == 0 || off > o.Count) throw new InvalidOperationException("bad offset");
            for (int k = 0; k < ml; k++) o.Add(o[o.Count - off]);
        }
        return o.ToArray();
    }
    public static string Text(string path) {
        try { return Encoding.GetEncoding(28591).GetString(Lz4(System.IO.File.ReadAllBytes(path), 20)); } catch { return null; }
    }
    public static Dictionary<string, string> Read(string path) {
        var result = new Dictionary<string, string>();
        byte[] raw = System.IO.File.ReadAllBytes(path); byte[] data;
        try { data = Lz4(raw, 20); } catch { return result; }   // 20-byte header, then the LZ4 payload
        string latin = Encoding.GetEncoding(28591).GetString(data);
        foreach (Match m in Regex.Matches(latin, "[A-Z]+_(?:TITLE|NAME)_[0-9]+_[0-9]+")) {
            int p = m.Index + m.Length;
            if (p + 4 > data.Length) continue;
            uint len = BitConverter.ToUInt32(data, p);
            if (len == 0 || len > 200 || p + 4 + len > data.Length) continue;
            result[m.Value] = Encoding.UTF8.GetString(data, p + 4, (int)len);
        }
        return result;
    }
}
'@
}

function Read-WfGameText([string]$Path, [string]$KeyPrefix) {
    try {
        $d = [WfGameText]::Read($Path)
        foreach ($k in $d.Keys) { if ($k.StartsWith($KeyPrefix)) { return $d[$k] } }
    } catch { }
    $null
}

# Returns @{ tracks = id -> "Venue - Layout"; weather = "data/property/weather/x.weat" -> name }. Empty when the game
# isn't installed or a file doesn't parse; the page then falls back to the ids.
function Get-WfNames([string]$ServerDir) {
    $tracks = [ordered]@{}; $weather = [ordered]@{}
    try {
        Initialize-WfGameText
        $evDir = Join-Path $ServerDir 'data\property\event'
        if (Test-Path $evDir) {
            $venues = @{}
            foreach ($f in Get-ChildItem $evDir -Recurse -Filter '*.envi') {
                $t = Read-WfGameText $f.FullName 'ENVIRONMENT_TITLE'
                if ($t) { $venues[$f.BaseName] = $t }
            }
            foreach ($f in Get-ChildItem $evDir -Recurse -Filter '*.evse') {
                $layout = Read-WfGameText $f.FullName 'EVENT_TITLE'
                if (-not $layout) { continue }
                $venue = $venues[($f.BaseName -replace '^(track\d+)_.*$', '$1')]
                $tracks[$f.BaseName] = if ($venue) { "$venue - $layout" } else { $layout }
            }
        }
        $wDir = Join-Path $ServerDir 'data\property\weather'
        if (Test-Path $wDir) {
            foreach ($f in Get-ChildItem $wDir -Filter '*.weat') {
                $n = Read-WfGameText $f.FullName 'WEATHER_NAME'
                if ($n) { $weather["data/property/weather/$($f.Name)"] = $n }
            }
        }
    } catch { }
    # AI sets and cars: friendly names from the .aist files (single-car sets are named after the car, e.g. car10 = Popper).
    $aiSets = [ordered]@{}; $cars = [ordered]@{}
    try {
        $aDir = Join-Path $ServerDir 'data\property\career\ai_sets'
        if (Test-Path $aDir) {
            foreach ($f in Get-ChildItem $aDir -Recurse -Filter '*.aist') {
                $n = Read-WfGameText $f.FullName ''
                if (-not $n) { continue }
                $rel = $f.FullName.Substring($aDir.Length + 1).Replace('\', '/')
                $aiSets["data/property/career/ai_sets/$rel"] = $n
                if ($rel -like 'singles/*') { $cars[$f.BaseName] = $n }
            }
        }
    } catch { }
    # The class sets are built into the game (no file); there are no names for them in the data, so these are descriptive.
    $aiSets['career/ai-class-all.aist'] = 'All classes'
    foreach ($c in 'a', 'b', 'c', 'd') { $aiSets["career/ai-class-$c.aist"] = "Class $($c.ToUpper()) cars" }
    [ordered]@{ tracks = $tracks; weather = $weather; aiSets = $aiSets; cars = $cars }
}

# Default game mode for each track, as the game itself sets it: the mode named in the track's event file, else the one in
# the game's own default rotation ('demolitionderby' there is the 'deathmatch' id used in the loop files), else bangerrace.
function Get-WfTrackModes([string]$ServerDir) {
    $modes = [ordered]@{}
    try {
        Initialize-WfGameText
        $evDir = Join-Path $ServerDir 'data\property\event'
        if (Test-Path $evDir) {
            foreach ($f in Get-ChildItem $evDir -Recurse -Filter '*.evse') {
                $t = [WfGameText]::Text($f.FullName)
                if ($t -and $t -match 'data/property/gamemode/([a-z0-9_]+)\.gmde') { $modes[$f.BaseName] = $Matches[1] }
            }
        }
        $rot = Join-Path $ServerDir 'data\property\settings\default_event_rotation.becl'
        if (Test-Path $rot) {
            foreach ($chunk in ([WfGameText]::Text($rot) -split 'lvlm')) {
                if ($chunk -match '(track\d+(?:_[a-z0-9]+)*)') {
                    $id = $Matches[1]
                    if (-not $modes.Contains($id)) { $modes[$id] = if ($chunk -match 'demolitionderby') { 'deathmatch' } else { 'bangerrace' } }
                }
            }
        }
    } catch { }
    $modes
}

# Which weather each track can use. Every event file names a weather list (.weli) and that list holds the .weat files
# allowed for the track, e.g. FinnCross Circuit (track01_1) -> track01_1.weat and track01_2.weat. The number in a weather
# file name is the weather variant, not the track layout. Returns track id -> weather paths, in the list's order.
function Get-WfWeatherByTrack([string]$ServerDir) {
    $map = [ordered]@{}
    try {
        Initialize-WfGameText
        $evDir = Join-Path $ServerDir 'data\property\event'
        $wDir = Join-Path $ServerDir 'data\property\weather'
        if (-not (Test-Path $evDir) -or -not (Test-Path $wDir)) { return $map }
        $lists = @{}
        foreach ($f in Get-ChildItem $wDir -Filter '*.weli') {
            $t = [WfGameText]::Text($f.FullName)
            if ($t) { $lists[$f.BaseName] = @([regex]::Matches($t, 'data/property/weather/([a-z0-9_]+\.weat)') | ForEach-Object { 'data/property/weather/' + $_.Groups[1].Value } | Select-Object -Unique) }
        }
        foreach ($f in Get-ChildItem $evDir -Recurse -Filter '*.evse') {
            if ($f.BaseName -eq 'menutrack') { continue }
            $t = [WfGameText]::Text($f.FullName)
            if ($t -and $t -match 'data/property/weather/([a-z0-9_]+)\.weli' -and $lists.ContainsKey($Matches[1])) { $map[$f.BaseName] = $lists[$Matches[1]] }
        }
    } catch { }
    $map
}

# Suggestions for the page's drop-downs: what the installed game ships plus whatever the config already uses.
function Get-WfChoices([string]$InstanceDir, [string]$ServerDir) {
    $levels  = New-Object 'Collections.Generic.SortedSet[string]'
    $weather = New-Object 'Collections.Generic.SortedSet[string]'
    $modes   = New-Object 'Collections.Generic.SortedSet[string]'
    $ai      = New-Object 'Collections.Generic.SortedSet[string]'
    $cars    = New-Object 'Collections.Generic.SortedSet[string]'
    # Every playable event has an .evse file (this includes variants like track02_2_sr that have no level folder of their
    # own). A level folder without one, such as track13_2_rev, isn't a playable event. Only fall back to the level
    # folders when the event files aren't there.
    $dir = Join-Path $ServerDir 'data\property\event'
    if (Test-Path $dir) { Get-ChildItem $dir -Recurse -Filter '*.evse' | Where-Object { $_.BaseName -ne 'menutrack' } | ForEach-Object { [void]$levels.Add($_.BaseName) } }
    else {
        $dir = Join-Path $ServerDir 'data\art\levels'
        if (Test-Path $dir) { Get-ChildItem $dir -Directory | Where-Object { $_.Name -ne 'mainmenu' } | ForEach-Object { [void]$levels.Add($_.Name) } }
    }
    $dir = Join-Path $ServerDir 'data\property\weather'
    if (Test-Path $dir) { Get-ChildItem $dir -Filter '*.weat' | ForEach-Object { [void]$weather.Add("data/property/weather/$($_.Name)") } }
    $dir = Join-Path $ServerDir 'data\property\career\ai_sets'
    if (Test-Path $dir) {
        Get-ChildItem $dir -Recurse -Filter '*.aist' | ForEach-Object { [void]$ai.Add('data/property/career/ai_sets/' + $_.FullName.Substring($dir.Length + 1).Replace('\', '/')) }
    }
    # AI sets the game's own rotations point at but that aren't loose files (for example quickchallenge/qc_folk_racing.aist).
    $settingsDir = Join-Path $ServerDir 'data\property\settings'
    try { Initialize-WfGameText } catch { }
    foreach ($f in @(Get-ChildItem (Join-Path $settingsDir 'cup') -Filter '*.becl' -ErrorAction SilentlyContinue) + @(Get-Item (Join-Path $settingsDir 'default_event_rotation.becl') -ErrorAction SilentlyContinue)) {
        $t = if ($f) { [WfGameText]::Text($f.FullName) } else { $null }
        if ($t) { foreach ($m in [regex]::Matches($t, 'data/property/career/ai_sets/[a-z0-9_/]+\.aist')) { [void]$ai.Add($m.Value) } }
    }
    foreach ($c in $WfAiClassSets) { [void]$ai.Add($c) }   # the built-in class sets (no file on disk)
    # Every car is a folder under data\vehicle (the shared folder holds common parts).
    $dir = Join-Path $ServerDir 'data\vehicle'
    if (Test-Path $dir) { Get-ChildItem $dir -Directory | Where-Object { $_.Name -ne 'shared' } | ForEach-Object { [void]$cars.Add($_.Name) } }
    $main = Join-Path $InstanceDir 'default_loop.template.becl'
    if (Test-Path $main) {
        foreach ($ev in (Read-WfJson $main).events) {
            foreach ($l in $ev.level) {
                if ($l.'level id') { [void]$levels.Add($l.'level id') }
                if ($l.'weather path') { [void]$weather.Add($l.'weather path') }
                if ($l.'game mode id') { [void]$modes.Add($l.'game mode id') }
                if ($l.'ai set path') { [void]$ai.Add((ConvertTo-WfAiSetPath $l.'ai set path')) }
            }
            foreach ($c in $ev.'car restriction') { if ($c.'allowed car type') { [void]$cars.Add($c.'allowed car type') } }
        }
    }
    foreach ($cup in (Read-WfCups $InstanceDir).cups) {
        foreach ($r in $cup.'car restriction') { if ($r.'allowed car type') { [void]$cars.Add($r.'allowed car type') } }
    }
    if (-not $script:WfNamesCache) { $script:WfNamesCache = Get-WfNames $ServerDir }   # decoded once per page start
    if (-not $script:WfTrackModes) { $script:WfTrackModes = Get-WfTrackModes $ServerDir }
    foreach ($m in $script:WfTrackModes.Values) { [void]$modes.Add($m) }
    if (-not $script:WfWeatherByTrack) { $script:WfWeatherByTrack = Get-WfWeatherByTrack $ServerDir }
    [ordered]@{
        names = $script:WfNamesCache
        trackModes = $script:WfTrackModes
        weatherByTrack = $script:WfWeatherByTrack
        levels = @($levels); weather = @($weather); modes = @($modes); aiSets = @($ai); cars = @($cars)
        # The three presets in the game's own damage list (damage_settings_list.vdsl).
        damage = @('normal', 'realistic', 'wrecker')
        # Start orders and collecting orders: read from the game's own string table (Wreckfest2.exe). 'random' and
        # 'points' are also used by the shipped cups; 'last race' sits next to 'last race reversed' in that table.
        startOrders = @('random', 'points', 'points reversed', 'last race', 'last race reversed')
        collectingOrders = @('Collecting None', 'Collecting Sequential', 'Collecting Random', 'Collecting Free')
    }
}
