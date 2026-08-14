#!/usr/bin/env bash
# 編譯論文成 PDF / HTML 預覽（Linux，實驗機可用）
# 需求：pandoc；PDF 另需 texlive-xetex + texlive-lang-chinese（xeCJK）。
#   SVG→PDF：先將 figs/*.svg 轉 PNG（rsvg-convert / inkscape）。
#   也可 `./build_pdf.sh html` 產 HTML 預覽（SVG 原生顯示）。
set -euo pipefail
cd "$(dirname "$0")"

FILES=(
  0_前頁.md
  ch01_緒論.md
  ch02_背景與相關研究.md
  ch03_系統設計-核心.md
  ch04_系統設計-進階機制與容錯.md
  ch05_實作.md
  ch06_實驗評估.md
  ch07_結論與未來工作.md
  附錄_量測協定與配置.md
  附錄B_失敗與修正紀錄.md
)

MODE="${1:-pdf}"
if [ "$MODE" = "html" ]; then
  pandoc "${FILES[@]}" -o thesis.html --embed-resources --standalone \
    --metadata-file=pandoc_meta.yaml --from markdown+raw_html
  echo "OK: thesis.html"
else
  pandoc "${FILES[@]}" -o thesis.pdf --metadata-file=pandoc_meta.yaml \
    --pdf-engine=xelatex
  echo "OK: thesis.pdf"
fi
