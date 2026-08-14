#!/usr/bin/env bash
# Build the thesis as PDF / HTML preview (Linux, also usable on the experiment machine)
# Requirements: pandoc; PDF additionally needs texlive-xetex + texlive-lang-chinese (xeCJK).
#   SVG→PDF: run scripts/svg2png.sh first (figs/*.png).
#   Or `scripts/build_pdf.sh html` for an HTML preview (SVG renders natively).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

FILES=(
  src/00-front.md
  src/ch01_introduction.md
  src/ch02_background.md
  src/ch03_design-core.md
  src/ch04_design-advanced.md
  src/ch05_implementation.md
  src/ch06_evaluation.md
  src/ch07_conclusion.md
  src/appendix-a.md
  src/appendix-b.md
)

META=src/pandoc_meta.yaml

MODE="${1:-pdf}"
LANG="${2:-en}"
SUFFIX=""
if [ "$LANG" = "en" ]; then
  FILES=(src_en/00-front.md src_en/ch01_introduction.md src_en/ch02_background.md src_en/ch03_design-core.md src_en/ch04_design-advanced.md src_en/ch05_implementation.md src_en/ch06_evaluation.md src_en/ch07_conclusion.md src_en/appendix-a.md src_en/appendix-b.md)
  META=src/pandoc_meta_en.yaml
  SUFFIX=_en
fi
if [ "$MODE" = "html" ]; then
  pandoc "${FILES[@]}" -o "thesis${SUFFIX}.html" --embed-resources --standalone \
    --metadata-file="$META" --from markdown+raw_html
  echo "OK: thesis${SUFFIX}.html"
elif [ "$MODE" = "docx" ]; then
  # Word edition: switch figure references from figs/*.svg to figs/*.png (Word cannot embed SVG).
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
