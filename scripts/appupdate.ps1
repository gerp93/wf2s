# Updating THIS app (the scripts and the page) from its GitHub releases. Dot-sourced by settings.ps1.
#
# The release zip carries a VERSION file (written by package.ps1 at build time). scripts\check-update.ps1 asks GitHub for the latest
# release and records it in latest-build.local; the page offers "Update app" when it is newer. The update itself is scripts\self-update.ps1.
# A copy run from git (it has a .git folder) has no VERSION and is updated with git pull, not by this.

$script:WfAppRepo        = 'gerp93/wf2s'
$script:WfAppAssetPrefix = 'https://github.com/gerp93/wf2s/releases/download/'

# 'v1.2.3' -> a Version, or $null when it is not a plain X.Y.Z
function ConvertTo-WfSemver([string]$Text) {
    if ("$Text".Trim() -match '^v?(\d+)\.(\d+)\.(\d+)$') { return (New-Object System.Version -ArgumentList ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3])) }
    $null
}
function Test-WfNewerVersion([string]$Current, [string]$Latest) {
    $a = ConvertTo-WfSemver $Current; $b = ConvertTo-WfSemver $Latest
    [bool]($a -and $b -and $b -gt $a)
}

function Get-WfAppVersion([string]$Root) {
    $f = Join-Path $Root 'VERSION'
    if (Test-Path $f) { return ([IO.File]::ReadAllText($f)).Trim() }
    ''
}
function Test-WfGitCheckout([string]$Root) { Test-Path (Join-Path $Root '.git') }

# The newest release's tag and its zip, from GitHub's "latest release" answer. $null for a draft, a pre-release or no matching zip.
function ConvertFrom-WfRelease($Release) {
    if (-not $Release -or $Release.draft -or $Release.prerelease) { return $null }
    $asset = @($Release.assets | Where-Object { $_.name -match '^wf2s-v\d+\.\d+\.\d+\.zip$' }) | Select-Object -First 1
    if (-not $asset -or -not (ConvertTo-WfSemver ([string]$Release.tag_name))) { return $null }
    [pscustomobject]@{
        tag       = [string]$Release.tag_name
        url       = [string]$asset.browser_download_url
        digest    = [string]$asset.digest      # "sha256:<hex>" when GitHub provides it
        published = [string]$Release.published_at
    }
}

# What the page shows about this app's own version.
function Get-WfAppInfo([string]$Root) {
    $f = Read-WfLatestBuildFile $Root
    $cur = Get-WfAppVersion $Root
    $git = Test-WfGitCheckout $Root
    [ordered]@{
        version         = $cur
        fromGit         = $git
        latest          = [string]$f.appLatest
        published       = [string]$f.appPublished
        updateAvailable = [bool]((-not $git) -and (Test-WfNewerVersion $cur ([string]$f.appLatest)))
    }
}

function Get-WfAppUpdateStatusFile([string]$Root) { Join-Path $Root 'app-update-status.local' }
function Read-WfAppUpdateStatus([string]$Root) {
    $f = Get-WfAppUpdateStatusFile $Root
    if (Test-Path $f) { try { return Read-WfJson $f } catch { } }
    [pscustomobject]@{ state = ''; message = ''; version = ''; at = '' }
}

# Starts scripts\self-update.ps1 as its own process (from a temporary copy, because it replaces the scripts, itself included) and
# returns at once. The updater downloads, checks and unpacks the release, then stops THIS settings page, swaps the files and starts
# the new page on the same port. Nothing is taken from the browser: the download address comes from the last check.
function Start-WfAppUpdate([string]$Root, [string]$Instance, [int]$Port) {
    if (Test-WfGitCheckout $Root) { throw 'This copy runs from a git checkout. Update it with git pull.' }
    $f = Read-WfLatestBuildFile $Root
    $cur = Get-WfAppVersion $Root
    if (-not $cur) { throw 'This copy has no VERSION file, so it cannot tell what to update to. Download the newest zip once.' }
    if (-not (Test-WfNewerVersion $cur ([string]$f.appLatest))) { throw 'No newer version is known. Click Check now first.' }
    $url = [string]$f.appUrl
    if (-not $url.StartsWith($script:WfAppAssetPrefix)) { throw 'The download address is not a release file of this project, so it was not used.' }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('wf2s-updater-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Copy-Item (Join-Path $Root 'scripts\self-update.ps1') $tmp
    $launch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $tmp 'self-update.ps1') + '"'),
        '-Root', ('"' + $Root + '"'), '-Url', ('"' + $url + '"'), '-Version', [string]$f.appLatest,
        '-UiPid', "$PID", '-Instance', $Instance, '-Port', "$Port")
    if ([string]$f.appDigest) { $launch += @('-Digest', ('"' + [string]$f.appDigest + '"')) }
    [IO.File]::WriteAllText((Get-WfAppUpdateStatusFile $Root), (ConvertTo-Json @{ state = 'running'; message = 'Starting the update...'; version = [string]$f.appLatest; at = [DateTime]::UtcNow.ToString('o') }), (New-Object Text.UTF8Encoding $false))
    $null = Start-Process powershell.exe -ArgumentList $launch -WorkingDirectory $tmp -WindowStyle Hidden
    [ordered]@{ started = $true; version = [string]$f.appLatest; message = 'Updating. The settings page restarts in a few seconds.' }
}
