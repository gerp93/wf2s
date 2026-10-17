# Usage: .\scripts\game-data-report.ps1
# Re-reads, from the INSTALLED game in .\server, every fact the settings page relies on and prints it with the file it came
# from. Run it after a game update to see what changed. docs/game-data-sources.md explains each fact and how sure we are.
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\settings.ps1"
if (-not (Test-Path "$Server\Wreckfest2.exe")) { throw "No game server in $Server. Run install.ps1 first." }
function Section([string]$t) { "`n== $t" }
function Row([string]$what, $value, [string]$source) { '{0,-46} {1,-14} {2}' -f $what, $value, $source }

Section 'Build'
$acf = Get-Content "$Server\steamapps\appmanifest_$AppId.acf" -ErrorAction SilentlyContinue
$build = ($acf | Select-String '"buildid"\s+"(\d+)"').Matches.Groups[1].Value
Row 'Steam build id' $build 'server\steamapps\appmanifest_3519390.acf'
Row 'Wreckfest2.exe size / modified' ("{0:N0} / {1:yyyy-MM-dd}" -f (Get-Item "$Server\Wreckfest2.exe").Length, (Get-Item "$Server\Wreckfest2.exe").LastWriteTime) 'server\Wreckfest2.exe'

Section 'Names and lists read from the data files (decoded: 20-byte header + LZ4, see the document)'
$ch = Get-WfChoices (Join-Path $Root 'instances\main') $Server
$n = $ch.names
Row 'Playable tracks (events)' @($ch.levels).Count 'server\data\property\event\**\*.evse (menutrack excluded)'
Row 'Tracks with a friendly name' $n.tracks.Count 'EVENT_TITLE in each .evse + ENVIRONMENT_TITLE in trackNN.envi'
Row 'Weather files / with a friendly name' ("{0} / {1}" -f @($ch.weather).Count, $n.weather.Count) 'server\data\property\weather\*.weat (WEATHER_NAME)'
Row 'Tracks with their own weather list' $ch.weatherByTrack.Count 'weather list named inside each .evse -> weather\*.weli'
Row 'AI sets with a name' $n.aiSets.Count 'server\data\property\career\ai_sets\**\*.aist'
Row 'Cars (vehicle folders) / with a name' ("{0} / {1}" -f @($ch.cars).Count, $n.cars.Count) 'server\data\vehicle\* ; names from ai_sets\singles\*.aist'
Row 'Game modes in use' ($ch.modes -join ', ') 'default_event_rotation.becl + .evse files + your loop'
$modeCount = $ch.trackModes.Values | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" }
Row 'Default mode per track' ($modeCount -join ' ') 'event\**\*.evse, settings\default_event_rotation.becl'
Initialize-WfGameText
$vd = [WfGameText]::Read("$Server\data\property\settings\damage_settings_list.vdsl")
Row 'Damage presets (names)' (($vd.Values) -join ', ') 'server\data\property\settings\damage_settings_list.vdsl'
Row 'Cups shipped (default cup list)' (@((Read-WfJson (Join-Path $Root 'defaults\server_cup_config.ccnl')).cups).Count) 'defaults\server_cup_config.ccnl (copy of the shipped list)'

Section 'Strings found in Wreckfest2.exe (its ASCII string table; the values the game recognises)'
$text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes("$Server\Wreckfest2.exe"))
$checks = [ordered]@{
    'Rule flags'                  = 'disable car resets', 'disable tuning', 'disable upgrades', 'disable wrong way limiter', 'disable special vehicles', 'disable class a', 'disable mechanical particle effects'
    'Car-restriction flags'       = 'reverse rule', 'disallow class a', 'disallow upgrades', 'disallow tuning'
    'Collecting orders'           = 'Collecting None', 'Collecting Sequential', 'Collecting Random', 'Collecting Free'
    'Start orders'                = 'random', 'points reversed', 'last race', 'last race reversed'
    'Core game mode categories'   = 'racing', 'derby'
    'Mode validation message'     = "Invalid game mode id '%s' for event %d"
    'Grid / participant limits'   = 'Grid size: %d/%d', 'Max participants reached!', 'Server full', 'Max clients reached', 'max client count'
    'Console: live commands'      = 'Print or set server name.', 'Print or set server description.', 'Reload the current event loop.', 'Reload cup config.', 'Cannot reload cup config when a cup is active', 'Change vehicle damage, or list damage types.', 'Invalid vehicle damage id!'
    'Start-up options'            = '--local-server', '--disable-online-server', '--save-dir', '--disable-eventloop'
}
foreach ($k in $checks.Keys) {
    $found = @($checks[$k] | Where-Object { $text.Contains($_) })
    Row $k ("{0}/{1}" -f $found.Count, @($checks[$k]).Count) ('missing: ' + ((@($checks[$k]) | Where-Object { $found -notcontains $_ }) -join '; '))
}

Section 'Not readable'
foreach ($pk in 'data00.rpck', 'data02.rpck') {
    $f = Get-Item "$Server\$pk" -ErrorAction SilentlyContinue
    if ($f) { Row "$pk (encrypted archive)" ('{0:N0} bytes' -f $f.Length) 'game modes (.gmde) and some AI sets live in packs like this; they cannot be read from disk' }
}
