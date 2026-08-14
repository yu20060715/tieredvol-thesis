import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const REPO = path.resolve(__dirname, '..')
const APP = path.resolve(__dirname)
const CONTENT = path.join(APP, 'src', 'content')
const PUBLIC = path.join(APP, 'public')

const DRIVER_DIR = process.env.TIEREDVOL_DRIVER
  ? path.resolve(process.env.TIEREDVOL_DRIVER)
  : path.resolve(REPO, '..', 'TieredVol-DRIVER')

const RENAME = {
  '0_前頁.md': '00-front.md',
  'ch01_緒論.md': 'ch01.md',
  'ch02_背景與相關研究.md': 'ch02.md',
  'ch03_系統設計-核心.md': 'ch03.md',
  'ch04_系統設計-進階機制與容錯.md': 'ch04.md',
  'ch05_實作.md': 'ch05.md',
  'ch06_實驗評估.md': 'ch06.md',
  'ch07_結論與貢獻總結.md': 'ch07.md',
  '附錄_量測協定與配置.md': 'appendix-a.md',
  '附錄B_失敗與修正紀錄.md': 'appendix-b.md',
}

function syncChapters(src, dst) {
  if (!fs.existsSync(src)) {
    console.warn('  missing source dir:', src)
    return 0
  }
  fs.rmSync(dst, { recursive: true, force: true })
  fs.mkdirSync(dst, { recursive: true })
  let n = 0
  for (const f of fs.readdirSync(src)) {
    if (!f.endsWith('.md')) continue
    if (f === '0_大綱.md') continue
    const out = RENAME[f] || f
    fs.copyFileSync(path.join(src, f), path.join(dst, out))
    n++
  }
  return n
}

function syncFigs(dst) {
  const src = path.join(REPO, 'figs')
  if (!fs.existsSync(src)) {
    console.warn('  missing figs dir:', src)
    return 0
  }
  fs.rmSync(dst, { recursive: true, force: true })
  fs.mkdirSync(dst, { recursive: true })
  let n = 0
  for (const f of fs.readdirSync(src)) {
    if (!f.endsWith('.svg')) continue
    fs.copyFileSync(path.join(src, f), path.join(dst, f))
    n++
  }
  return n
}

function syncDriver(dst) {
  if (!fs.existsSync(DRIVER_DIR)) {
    console.warn('  missing DRIVER repo, skip:', DRIVER_DIR)
    return 0
  }
  fs.rmSync(dst, { recursive: true, force: true })
  fs.mkdirSync(dst, { recursive: true })
  const files = {
    'README.md': 'overview.md',
    'docs/ARCHITECTURE.md': 'ARCHITECTURE.md',
    'docs/CONFIG.md': 'CONFIG.md',
    'docs/DESIGN.md': 'DESIGN.md',
    'docs/KERNEL_TESTS.md': 'KERNEL_TESTS.md',
    'docs/MAPPING.md': 'MAPPING.md',
    'docs/MIRROR.md': 'MIRROR.md',
    'docs/PARTITION_SPLITTING.md': 'PARTITION_SPLITTING.md',
    'docs/RESULTS.md': 'RESULTS.md',
    'docs/ROADMAP.md': 'ROADMAP.md',
    'docs/SUPPLEMENTARY_20260814.md': 'SUPPLEMENTARY.md',
    'docs/TEST_PLAN.md': 'TEST_PLAN.md',
    'docs/WC.md': 'WC.md',
  }
  let n = 0
  for (const [f, out] of Object.entries(files)) {
    const s = path.join(DRIVER_DIR, f)
    if (!fs.existsSync(s)) {
      console.warn('  skip (missing):', f)
      continue
    }
    fs.copyFileSync(s, path.join(dst, out))
    n++
  }
  return n
}

function touch(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, '')
}

const zh = syncChapters(path.join(REPO, 'src'), path.join(CONTENT, 'zh', 'chapters'))
const en = syncChapters(path.join(REPO, 'src_en'), path.join(CONTENT, 'en', 'chapters'))
const figs = syncFigs(path.join(PUBLIC, 'figs'))
const drv = syncDriver(path.join(CONTENT, 'driver'))
touch(path.join(PUBLIC, '.nojekyll'))

console.log(`sync done: zh=${zh} en=${en} figs=${figs} driver=${drv}`)
