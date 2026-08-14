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
  src/ch07_結論與貢獻總結.md
  src/附錄_量測協定與配置.md
  src/附錄B_失敗與修正紀錄.md
)

META=src/pandoc_meta.yaml

MODE="${1:-pdf}"
LANG="${2:-zh}"
SUFFIX=""
if [ "$LANG" = "en" ]; then
  FILES=(src_en/0_前頁.md src_en/ch01_緒論.md src_en/ch02_背景與相關研究.md src_en/ch03_系統設計-核心.md src_en/ch04_系統設計-進階機制與容錯.md src_en/ch05_實作.md src_en/ch06_實驗評估.md src_en/ch07_結論與貢獻總結.md src_en/附錄_量測協定與配置.md src_en/附錄B_失敗與修正紀錄.md)
  META=src/pandoc_meta_en.yaml
  SUFFIX=_en
fi
if [ "$MODE" = "html" ]; then
  pandoc "${FILES[@]}" -o "thesis${SUFFIX}.html" --embed-resources --standalone \
    --metadata-file="$META" --from markdown+raw_html
  echo "OK: thesis${SUFFIX}.html"
elif [ "$MODE" = "docx" ]; then
  # Word 版：SVG 圖改引用 figs/*.png（Word 無法內嵌 SVG）。
  TMP="$(mktemp -d)"
  TMPFILES=()
  for f in "${FILES[@]}"; do
    out="$TMP/$(basename "$f")"
    sed -E 's#figs/(F[[:alnum:]_]+)\.svg#\1.png#g' "$f" > "$out"
    TMPFILES+=("$out")
  done
  pandoc "${TMPFILES[@]}" -o "thesis${SUFFIX}.docx" --toc --metadata-file="$META" \
    --resource-path=figs --from markdown+raw_html
  rm -rf "$TMP"
  echo "OK: thesis${SUFFIX}.docx"
else
  pandoc "${FILES[@]}" -o "thesis${SUFFIX}.pdf" --metadata-file="$META" \
    --pdf-engine=xelatex
  echo "OK: thesis${SUFFIX}.pdf"
fi
