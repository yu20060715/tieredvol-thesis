# 異質磁碟之加權條帶化裝置映射與性能模型

以 Linux Device Mapper 實作的加權條帶化（weighted striped）異質磁碟映射層，
碩士論文（國立雲林科技大學 資訊工程系）。

## 目錄結構

```
TieredVol-thesis/
├── src/                    # 論文原始文字檔（Markdown）
│   ├── 0_前頁.md           # 封面 / 摘要 / 目錄前頁
│   ├── 0_大綱.md           # 全文結構總覽（章節地圖）
│   ├── ch01_緒論.md
│   ├── ch02_背景與相關研究.md
│   ├── ch03_系統設計-核心.md
│   ├── ch04_系統設計-進階機制與容錯.md
│   ├── ch05_實作.md
│   ├── ch06_實驗評估.md
│   ├── ch07_結論與未來工作.md
│   ├── 附錄_量測協定與配置.md
│   ├── 附錄B_失敗與修正紀錄.md
│   └── pandoc_meta.yaml    # pandoc 元資料（標題、字型、版面）
├── figs/                   # 圖檔原始檔（SVG）
├── scripts/                # 建置與工具腳本
│   ├── build_pdf.ps1       # Windows：建 PDF / HTML 預覽
│   ├── build_pdf.sh        # Linux：建 PDF / HTML 預覽
│   └── svg2png.ps1         # Windows：SVG → PNG（PDF 用）
├── thesis.html             # 建置產物（gitignore，可再生成）
├── thesis.pdf              # 建置產物（gitignore，可再生成）
└── .gitignore
```

## 建置

需求：`pandoc`；PDF 另需 `xelatex`（TeX Live / MiKTeX）＋中文字型。

```bash
# HTML 預覽（SVG 原生渲染，推薦先看版面）
scripts/build_pdf.ps1 html        # Windows PowerShell
./scripts/build_pdf.sh html       # Linux

# PDF（LaTeX 排版）——Windows 需先轉 PNG
scripts/svg2png.ps1               # 先將 figs/*.svg 轉 PNG
scripts/build_pdf.ps1             # 再建 PDF

# PDF 預覽（不需 TeX，用 Chrome headless）
scripts/build_pdf.ps1 chrome
```

## 實驗數據出處

論文第六章的數據來自實驗機儲存庫 `TieredVol-DRIVER` 的
`docs/RESULTS.md` 與 `docs/data/`（原始量測）。修改任何數字前請先比對出處。

## 相關儲存庫

- 驅動程式與實驗：https://github.com/yu20060715/TieredVol-DRIVER
- 本論文：https://github.com/yu20060715/tieredvol-thesis
