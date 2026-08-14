# Build thesis PDF / HTML preview (Windows).
# Requirements: pandoc; for PDF also xelatex (TeX Live or MiKTeX) + xeCJK fonts.
# NOTE: SVG figures cannot be embedded by xelatex PDF directly -
#   PDF: run .\svg2png.ps1 first (figs/*.png), then build.
#   HTML: --self-contained renders SVG natively; use this for layout preview.
$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$lang = if ($args.Count -gt 1) { $args[1] } else { "en" }

if ($lang -eq "en") {
  $files = @(
    "src_en/00-front.md",
    "src_en/ch01_introduction.md",
    "src_en/ch02_background.md",
    "src_en/ch03_design-core.md",
    "src_en/ch04_design-advanced.md",
    "src_en/ch05_implementation.md",
    "src_en/ch06_evaluation.md",
    "src_en/ch07_conclusion.md",
    "src_en/appendix-a.md",
    "src_en/appendix-b.md"
  )
  $meta = "src/pandoc_meta_en.yaml"
  $suffix = "_en"
} else {
  $files = @(
    "src/00-front.md",
    "src/ch01_introduction.md",
    "src/ch02_background.md",
    "src/ch03_design-core.md",
    "src/ch04_design-advanced.md",
    "src/ch05_implementation.md",
    "src/ch06_evaluation.md",
    "src/ch07_conclusion.md",
    "src/appendix-a.md",
    "src/appendix-b.md"
  )
  $meta = "src/pandoc_meta.yaml"
  $suffix = ""
}

$mode = if ($args.Count -gt 0) { $args[0] } else { "pdf" }
if ($mode -eq "html") {
  pandoc @files -o thesis$suffix.html --embed-resources --standalone --metadata-file=$meta --from markdown+raw_html
  if ($?) { Write-Host "OK: thesis$suffix.html (open in browser; SVG figures render natively)" }
} elseif ($mode -eq "chrome") {
  # PDF preview without TeX: build HTML first, then print it with headless Chrome.
  pandoc @files -o thesis$suffix.html --embed-resources --standalone --metadata-file=$meta --from markdown+raw_html
  $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
  if (-not (Test-Path $chrome)) { $chrome = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe" }
  $url = "file:///$((Resolve-Path thesis$suffix.html).Path -replace '\\','/')"
  & $chrome --headless=new --disable-gpu --no-sandbox --print-to-pdf="$repo\thesis$suffix.pdf" $url 2>$null | Out-Null
  if (Test-Path thesis$suffix.pdf) { Write-Host "OK: thesis$suffix.pdf (Chrome preview, not LaTeX typeset)" }
} elseif ($mode -eq "docx") {
  # Word edition: switch figure references from figs/*.svg to figs/*.png (Word cannot embed SVG).
  $tmp = Join-Path $repo ".docx_tmp"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $tmpFiles = @()
  foreach ($f in $files) {
    $out = Join-Path $tmp (Split-Path -Leaf $f)
    (Get-Content -Raw -Encoding UTF8 $f) -replace 'figs/(F[\w]+)\.svg', '$1.png' | Set-Content -Encoding UTF8 $out
    $tmpFiles += $out
  }
  pandoc @tmpFiles -o thesis$suffix.docx --toc --metadata-file=$meta --resource-path=figs --from markdown+raw_html
  Remove-Item -Recurse -Force $tmp
  if (Test-Path thesis$suffix.docx) { Write-Host "OK: thesis$suffix.docx (tables + PNG figures)" }
} else {
  # PDF (xelatex): cannot embed SVG, so switch figure references to figs/*.png (run svg2png.ps1 first).
  $tmp = Join-Path $repo ".pdf_tmp"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $tmpFiles = @()
  foreach ($f in $files) {
    $out = Join-Path $tmp (Split-Path -Leaf $f)
    (Get-Content -Raw -Encoding UTF8 $f) -replace 'figs/(F[\w]+)\.svg', '$1.png' | Set-Content -Encoding UTF8 $out
    $tmpFiles += $out
  }
  pandoc @tmpFiles -o thesis$suffix.pdf --metadata-file=$meta --pdf-engine=xelatex --resource-path=figs
  Remove-Item -Recurse -Force $tmp
  if (Test-Path thesis$suffix.pdf) { Write-Host "OK: thesis$suffix.pdf (xelatex)" }
}
