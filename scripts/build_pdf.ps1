# Build thesis PDF / HTML preview (Windows).
# Requirements: pandoc; for PDF also xelatex (TeX Live or MiKTeX) + xeCJK fonts.
# NOTE: SVG figures cannot be embedded by xelatex PDF directly -
#   PDF: run .\svg2png.ps1 first (figs/*.png), then build.
#   HTML: --self-contained renders SVG natively; use this for layout preview.
$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$files = @(
  "src/0_前頁.md",
  "src/ch01_緒論.md",
  "src/ch02_背景與相關研究.md",
  "src/ch03_系統設計-核心.md",
  "src/ch04_系統設計-進階機制與容錯.md",
  "src/ch05_實作.md",
  "src/ch06_實驗評估.md",
  "src/ch07_結論與開放問題.md",
  "src/附錄_量測協定與配置.md",
  "src/附錄B_失敗與修正紀錄.md"
)

$meta = "src/pandoc_meta.yaml"

$mode = if ($args.Count -gt 0) { $args[0] } else { "pdf" }
if ($mode -eq "html") {
  pandoc @files -o thesis.html --embed-resources --standalone --metadata-file=$meta --from markdown+raw_html
  if ($?) { Write-Host "OK: thesis.html (open in browser; SVG figures render natively)" }
} elseif ($mode -eq "chrome") {
  # 不需 TeX 的 PDF 預覽：先建 HTML，再用 Chrome headless 印成 PDF。
  pandoc @files -o thesis.html --embed-resources --standalone --metadata-file=$meta --from markdown+raw_html
  $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
  if (-not (Test-Path $chrome)) { $chrome = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe" }
  $url = "file:///$((Resolve-Path thesis.html).Path -replace '\\','/')"
  & $chrome --headless=new --disable-gpu --no-sandbox --print-to-pdf="$repo\thesis.pdf" $url 2>$null | Out-Null
  if (Test-Path thesis.pdf) { Write-Host "OK: thesis.pdf (Chrome 預覽，非 LaTeX 排版)" }
} else {
  pandoc @files -o thesis.pdf --metadata-file=$meta --pdf-engine=xelatex
  if ($?) { Write-Host "OK: thesis.pdf (note: run svg2png.ps1 first to convert SVG figures)" }
}
