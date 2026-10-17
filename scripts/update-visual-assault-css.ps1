# Usage: .\scripts\update-visual-assault-css.ps1 v0.2.0
# Re-vendors ui/vendor/visual-assault-themes.css from a VisualAssault tag (https://github.com/gerp93/VisualAssault).
# Never edit the vendored file by hand.
param([Parameter(Mandatory)][ValidatePattern('^v\d+\.\d+\.\d+$')][string]$Tag)
. "$PSScriptRoot\common.ps1"
$url = "https://raw.githubusercontent.com/gerp93/VisualAssault/$Tag/packages/css/themes.css"
$css = (Invoke-WebRequest -UseBasicParsing $url).Content
if ($css -isnot [string]) { $css = [Text.Encoding]::UTF8.GetString($css) }
$header = "/* Vendored from gerp93/VisualAssault packages/css/themes.css @ $Tag`n" +
          "   Source: https://github.com/gerp93/VisualAssault/blob/$Tag/packages/css/themes.css`n" +
          "   Do not hand-edit. Re-vendor with scripts/update-visual-assault-css.ps1 <tag> */`n`n"
$out = Join-Path $Root 'ui\vendor\visual-assault-themes.css'
[IO.File]::WriteAllText($out, $header + $css.TrimStart([char]0xFEFF), (New-Object Text.UTF8Encoding $false))
Write-Host "Wrote $out ($Tag)"
