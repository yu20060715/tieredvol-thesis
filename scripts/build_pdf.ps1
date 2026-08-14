# Build thesis PDF / HTML preview (Windows).
# Requirements: pandoc; for PDF also xelatex (TeX Live or MiKTeX) + xeCJK fonts.
# NOTE: SVG figures cannot be embedded by xelatex PDF directly -
#   PDF: run .\svg2png.ps1 first (figs/*.png), then build.
#   HTML: --self-contained renders SVG natively; use this for layout preview.
$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$lang = if ($args.Count -gt 1) { $args[1] } else { "zh" }

if ($lang -eq "en") {
  $files = @(
    "src_en/0_前頁.md",
    "src_en/ch01_緒論.md",
    "src_en/ch02_背景與相關研究.md",
    "src_en/ch03_系統設計-核心.md",
    "src_en/ch04_系統設計-進階機制與容錯.md",
    "src_en/ch05_實作.md",
    "src_en/ch06_實驗評估.md",
    "src_en/ch07_結論與貢獻總結.md",
    "src_en/附錄_量測協定與配置.md",
    "src_en/附錄B_失敗與修正紀錄.md"
  )
  $meta = "src/pandoc_meta_en.yaml"
  $suffix = "_en"
} else {
  $files = @(
    "src/0_前頁.md",
    "src/ch01_緒論.md",
    "src/ch02_背景與相關研究.md",
    "src/ch03_系統設計-核心.md",
    "src/ch04_系統設計-進階機制與容錯.md",
    "src/ch05_實作.md",
    "src/ch06_實驗評估.md",
    "src/ch07_結論與貢獻總結.md",
    "src/附錄_量測協定與配置.md",
    "src/附錄B_失敗與修正紀錄.md"
  )
  $meta = "src/pandoc_meta.yaml"
  $suffix = ""
}

$mode = if ($args.Count -gt 0) { $args[0] } else { "pdf" }
if ($mode -eq "html") {
  pandoc @files -o thesis$suffix.html --embed-resources --standalone --metadata-file=$meta --from markdown+raw_html
  if ($?) { Write-Host "OK: thesis$suffix.html (open in browser; SVG figures render natively)" }
} elseif ($mode -eq "chrome") {
  # 不需 TeX 的 PDF 預覽：先建 HTML，再用 Chrome headless 印成 PDF。
  pandoc @files -o thesis$suffix.html --embed-resources --standalone --metadata-file=$meta --from markdown+raw_html
  $chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
  if (-not (Test-Path $chrome)) { $chrome = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe" }
  $url = "file:///$((Resolve-Path thesis$suffix.html).Path -replace '\\','/')"
  & $chrome --headless=new --disable-gpu --no-sandbox --print-to-pdf="$repo\thesis$suffix.pdf" $url 2>$null | Out-Null
  if (Test-Path thesis$suffix.pdf) { Write-Host "OK: thesis$suffix.pdf (Chrome 預覽，非 LaTeX 排版)" }
} elseif ($mode -eq "docx") {
  # Word 版：SVG 圖改引用 figs/*.png（Word 無法內嵌 SVG）。
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
  pandoc @files -o thesis$suffix.pdf --metadata-file=$meta --pdf-engine=xelatex
  if ($?) { Write-Host "OK: thesis$suffix.pdf (note: run svg2png.ps1 first to convert SVG figures)" }
}
