#!/usr/bin/env bash
# 編譯論文成 PDF / HTML 預覽（Linux，實驗機可用）
# 需求：pandoc；PDF 另需 texlive-xetex + texlive-lang-chinese（xeCJK）。
#   SVG→PDF：先執行 scripts/svg2png.sh（figs/*.png）。
#   也可 `scripts/build_pdf.sh html` 產 HTML 預覽（SVG 原生顯示）。
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

FILES=(
  src/0_前頁.md
  src/ch01_緒論.md
  src/ch02_背景與相關研究.md
  src/ch03_系統設計-核心.md
  src/ch04_系統設計-進階機制與容錯.md
  src/ch05_實作.md
  src/ch06_實驗評估.md
  src/ch07_結論與未來工作.md
  src/附錄_量測協定與配置.md
  src/附錄B_失敗與修正紀錄.md
)

META=src/pandoc_meta.yaml

MODE="${1:-pdf}"
if [ "$MODE" = "html" ]; then
  pandoc "${FILES[@]}" -o thesis.html --embed-resources --standalone \
    --metadata-file="$META" --from markdown+raw_html
  echo "OK: thesis.html"
else
  pandoc "${FILES[@]}" -o thesis.pdf --metadata-file="$META" \
    --pdf-engine=xelatex
  echo "OK: thesis.pdf"
fi
