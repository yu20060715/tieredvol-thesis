# Build thesis PDF / HTML preview (Windows).
# Requirements: pandoc; for PDF also xelatex (TeX Live or MiKTeX) + xeCJK fonts.
# NOTE: SVG figures cannot be embedded by xelatex PDF directly -
#   PDF: convert figs/*.svg to PNG first (Inkscape / rsvg-convert / browser).
#   HTML: --self-contained renders SVG natively; use this for layout preview.
$ErrorActionPreference = "Continue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $dir

$files = @(
  "0_前頁.md",
  "ch01_緒論.md",
  "ch02_背景與相關研究.md",
  "ch03_系統設計-核心.md",
  "ch04_系統設計-進階機制與容錯.md",
  "ch05_實作.md",
  "ch06_實驗評估.md",
  "ch07_結論與未來工作.md",
  "附錄_量測協定與配置.md",
  "附錄B_失敗與修正紀錄.md"
)

$mode = if ($args.Count -gt 0) { $args[0] } else { "pdf" }
if ($mode -eq "html") {
  pandoc @files -o thesis.html --embed-resources --standalone --metadata-file=pandoc_meta.yaml --from markdown+raw_html
  if ($?) { Write-Host "OK: thesis.html (open in browser; SVG figures render natively)" }
} elseif ($mode -eq "chrome") {
  # 不需 TeX 的 PDF 預覽：先建 HTML，再用 Chrome headless 印成 PDF。
  pandoc @files -o thesis.html --embed-resources --standalone --metadata-file=pandoc_meta.yaml --from markdown+raw_html
  $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
  if (-not (Test-Path $chrome)) { $chrome = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe" }
  $url = "file:///$((Resolve-Path thesis.html).Path -replace '\\','/')"
  & $chrome --headless=new --disable-gpu --no-sandbox --print-to-pdf="$dir\thesis.pdf" $url 2>$null | Out-Null
  if (Test-Path thesis.pdf) { Write-Host "OK: thesis.pdf (Chrome 預覽，非 LaTeX 排版)" }
} else {
  pandoc @files -o thesis.pdf --metadata-file=pandoc_meta.yaml --pdf-engine=xelatex
  if ($?) { Write-Host "OK: thesis.pdf (note: convert SVG figures to PNG first if any)" }
}
