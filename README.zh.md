# 異質磁碟之加權條帶化裝置映射與性能模型

以 Linux Device Mapper 實作的加權條帶化（weighted striped）異質磁碟映射層：
確定性 O(1) 無表映射、瓶頸性能模型、動態權重借調、鏡像與小寫入快取。
本儲存庫為碩士論文（國立雲林科技大學 資訊工程系）之 Markdown 原始檔。

[English](README.md)

## 目錄結構

```
TieredVol-thesis/
├── src/                       # 中文版章節原始檔（Markdown）
│   ├── 00-front.md            # 封面 / 摘要 / 符號表 / 縮寫表
│   ├── outline.md             # 全文結構總覽（章節地圖，僅中文工作檔）
│   ├── ch01_introduction.md
│   ├── ch02_background.md
│   ├── ch03_design-core.md
│   ├── ch04_design-advanced.md
│   ├── ch05_implementation.md
│   ├── ch06_evaluation.md
│   ├── ch07_conclusion.md
│   ├── appendix-a.md          # 量測協定與配置手冊
│   ├── appendix-b.md          # 失敗與修正紀錄
│   ├── pandoc_meta.yaml       # pandoc 元資料（中文版建置）
│   └── pandoc_meta_en.yaml    # pandoc 元資料（英文版建置）
├── src_en/                    # 每章英文翻譯（同名檔）
├── figs/                      # 圖檔原始檔（SVG）；F1–F12 及 *_en 英文版
├── scripts/                   # 建置與工具腳本
│   ├── build_pdf.ps1          # Windows：建 PDF / HTML 預覽 / DOCX
│   ├── build_pdf.sh           # Linux：建 PDF / HTML 預覽 / DOCX
│   └── svg2png.ps1            # Windows：SVG → PNG（PDF / DOCX 用）
├── website/                   # 中英雙語（en/zh）靜態網站 — Vite + Vue 3
└── .github/workflows/deploy.yml  # GitHub Pages 部署
```

建置產物（`thesis*`、`figs/*.png`）已 gitignore，由腳本再生成。

## 建置

需求：`pandoc`；PDF 另需 `xelatex`（TeX Live / MiKTeX）＋中文字型。

**英文為預設建置語言**；要建中文版請在指令後加 `zh`。

```bash
# HTML 預覽（SVG 原生渲染，推薦先看版面）
scripts/build_pdf.ps1 html        # Windows PowerShell → 英文
scripts/build_pdf.ps1 html zh     # → 中文
./scripts/build_pdf.sh html       # Linux

# DOCX（Word；圖引用由 SVG 改為 PNG）
scripts/svg2png.ps1               # 先將 figs/*.svg 轉 PNG
scripts/build_pdf.ps1 docx        # → thesis_en.docx（英文）
scripts/build_pdf.ps1 docx zh     # → thesis.docx（中文）

# PDF（LaTeX）
scripts/build_pdf.ps1             # 英文（先跑 svg2png.ps1）
scripts/build_pdf.ps1 pdf zh      # 中文

# PDF 預覽（不需 TeX，用 Chrome headless）
scripts/build_pdf.ps1 chrome
```

## 網站

`website/` 為 Vite + Vue 3 SPA（hash router、en/zh 雙語）。內容由
`src/`、`src_en/`、`figs/` 與 DRIVER 儲存庫同步：

```bash
node website/sync.mjs         # 複製章節與圖檔至 website/src/content
cd website && npm run build   # 產出正式版（dist/）
```

部署由 GitHub Actions（`.github/workflows/deploy.yml`）自動執行，並會同步
`yu20060715/TieredVol-DRIVER` 的驅動程式文件。

## 實驗數據出處

論文第六章的數據來自實驗機儲存庫 `TieredVol-DRIVER` 的
`docs/RESULTS.md` 與 `docs/data/`（原始量測）。修改任何數字前請先比對出處。

## 相關儲存庫

- 驅動程式與實驗：https://github.com/yu20060715/TieredVol-DRIVER
- 本論文：https://github.com/yu20060715/tieredvol-thesis
