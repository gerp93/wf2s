# Smoke test for the installer on a clean machine (CI runs this): silent install into a temp folder, check what it laid down, create
# some "user data", silent uninstall, check the app is gone and the data is not. Never run it against a folder you care about.
# Usage: .\scripts\test-installer.ps1 -Setup dist\wf2s-setup-v1.2.3.exe -Version v1.2.3
param([Parameter(Mandatory)][string]$Setup, [Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
$Setup = [IO.Path]::GetFullPath($Setup)
$dir = Join-Path ([IO.Path]::GetTempPath()) ('wf2s-install-test-' + [guid]::NewGuid().ToString('N'))
$fail = 0
function Check([string]$what, [bool]$ok) { if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what" -ForegroundColor Red; $script:fail++ } }
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Wreckfest 2 Server.lnk'

try {
    Write-Host 'Install (silent, per user)'
    $p = Start-Process $Setup -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/TASKS=""', "/DIR=`"$dir`"", "/LOG=`"$dir.install.log`"") -Wait -PassThru
    Check 'setup exits 0' ($p.ExitCode -eq 0)
    Check 'Start.cmd installed' (Test-Path (Join-Path $dir 'Start.cmd'))
    Check 'scripts installed' (Test-Path (Join-Path $dir 'scripts\setup.ps1'))
    Check 'self-update.ps1 installed' (Test-Path (Join-Path $dir 'scripts\self-update.ps1'))
    Check 'the page installed' (Test-Path (Join-Path $dir 'ui\index.html'))
    Check 'default instance installed' (Test-Path (Join-Path $dir 'defaults\instance\server_config.template.scnf'))
    Check 'VERSION is stamped' ((Test-Path (Join-Path $dir 'VERSION')) -and (([IO.File]::ReadAllText((Join-Path $dir 'VERSION'))).Trim() -eq $Version))
    Check 'Start Menu shortcut created' (Test-Path $startMenu)
    Check 'nothing personal or from the game was installed' (-not (Test-Path (Join-Path $dir 'instances')) -and -not (Test-Path (Join-Path $dir 'server')) -and -not (Get-ChildItem $dir -Recurse -Filter '*.local' -ErrorAction SilentlyContinue))
    Check 'uninstaller installed' (Test-Path (Join-Path $dir 'unins000.exe'))
    Check 'conhost.exe (used to open the setup window) exists' ($null -ne (Get-Command conhost.exe -ErrorAction SilentlyContinue))

    Write-Host 'The installed copy works'
    $pw = ConvertTo-SecureString 'installer-test' -AsPlainText -Force
    & "$dir\scripts\setup.ps1" -Instance ci -SkipInstall -SkipFirewall -NoPrompt -ServerName 'Installer test' -Password $pw *>&1 | Out-Null
    Check 'setup runs from the installed folder' (($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $dir 'instances\ci\password.local')) -and (Test-Path (Join-Path $dir 'instances\ci\default_loop.template.becl')))

    Write-Host 'Uninstall (silent keeps your data)'
    $u = Start-Process (Join-Path $dir 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    Start-Sleep -Seconds 2   # the uninstaller finishes by re-launching itself from a temp copy
    for ($i = 0; $i -lt 20 -and (Test-Path (Join-Path $dir 'scripts')); $i++) { Start-Sleep -Milliseconds 500 }
    Check 'uninstaller exits 0' ($u.ExitCode -eq 0)
    Check 'the app files are gone' (-not (Test-Path (Join-Path $dir 'scripts')) -and -not (Test-Path (Join-Path $dir 'Start.cmd')) -and -not (Test-Path (Join-Path $dir 'ui')))
    Check 'your server data is kept' (Test-Path (Join-Path $dir 'instances\ci\password.local'))
    Check 'the Start Menu shortcut is gone' (-not (Test-Path $startMenu))
} finally {
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$dir.install.log" -Force -ErrorAction SilentlyContinue
}
if ($fail) { Write-Host "$fail check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'Installer checks passed.' -ForegroundColor Green
