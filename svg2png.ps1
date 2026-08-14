# Convert all figs/*.svg to PNG using headless Chrome (Windows).
# Usage: .\svg2png.ps1 [width,height per figure as "WxH"]
$ErrorActionPreference = "Continue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$figs = Join-Path $dir "figs"
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) {
  $chrome = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
}
if (-not (Test-Path $chrome)) {
  Write-Host "Chrome/Edge not found; cannot convert SVG."
  exit 1
}
Get-ChildItem (Join-Path $figs "*.svg") | ForEach-Object {
  $svg = $_.FullName
  $png = [System.IO.Path]::ChangeExtension($svg, ".png")
  $w = 960
  $h = 700
  if ($args.Count -gt 0) {
    $parts = $args[0] -split "x"
    $w = $parts[0]; if ($parts.Count -gt 1) { $h = $parts[1] }
  }
  & $chrome --headless=new --disable-gpu `
    --screenshot=$png --window-size="$w,$h" `
    "file:///$($svg -replace '\\','/')" 2>$null | Out-Null
  if (Test-Path $png) {
    Write-Host ("OK {0} -> {1} ({2:N0} B)" -f $_.Name, (Split-Path $png -Leaf), (Get-Item $png).Length)
  } else {
    Write-Host ("ERR {0}" -f $_.Name)
  }
}
