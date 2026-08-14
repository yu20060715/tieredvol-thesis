export const mainTable = [
  { name: 'S1', disks: 1, weight: '1', write: 2080, read: 3112, protocol: 'P3' },
  { name: 'S2', disks: 2, weight: '37:27', write: 3547, read: 3899, protocol: 'P3' },
  { name: 'S3', disks: 3, weight: '64:30:10', write: 3370, read: 4323, protocol: 'P3' },
  { name: 'S4', disks: 4, weight: '64:27:9:4', write: 3300, read: 4292, protocol: 'P1' },
  { name: 'MIR', disks: 1, weight: '1:1', write: 457, read: 3799, protocol: 'P3' },
]

export const protocolLabels = {
  all: { zh: '全部', en: 'All' },
  P1: { zh: 'P1（排水態）', en: 'P1 (drain state)' },
  P3: { zh: 'P3（冷態＋空檔）', en: 'P3 (cold state + idle)' },
}

export const staircase = [2078, 2410, 2896, 3006]
export const staircaseConfigs = ['10:2', '20:4:5', '56:11:14:6']

export const autoWeight = [
  { config: 'S2', weight: '10:2', model: 2468, measured: 2410, deviation: -2.4, util: 97.6 },
  { config: 'S3', weight: '20:4:5', model: 2982, measured: 2896, deviation: -2.9, util: 96.9 },
  { config: 'S4', weight: '56:11:14:6', model: 3194, measured: 3006, deviation: -5.9, util: 93.7 },
]

export const dmi = {
  proportional: 2561,
  aware: 3370,
  model: 3364,
  budget: 1300,
}

export const lvmCompare = {
  lvm: { write: 1616, read: 1791 },
  tieredCold: { write: 3091, read: 3575 },
  tieredDrain: { write: 3300, read: 4292 },
}

export const randMixed = [
  {
    title: { zh: '4K 隨機寫入', en: '4K random write' },
    rows: [
      { name: 'TieredVol S4', value: 663, unit: 'MiB/s' },
      { name: 'LVM striped', value: 570, unit: 'MiB/s' },
      { name: 'A solo', value: 812, unit: 'MiB/s' },
    ],
  },
  {
    title: { zh: '4K 隨機讀取', en: '4K random read' },
    rows: [
      { name: 'TieredVol S4', value: 680, unit: 'MiB/s' },
      { name: 'LVM striped', value: 496, unit: 'MiB/s' },
      { name: 'A solo', value: 533, unit: 'MiB/s' },
    ],
  },
  {
    title: { zh: '1M 混寫混讀', en: '1M mixed read/write' },
    rows: [
      { name: 'TieredVol S4', value: 'R 1149 / W 1175', unit: 'MiB/s' },
      { name: 'LVM striped', value: 'R 366 / W 375', unit: 'MiB/s' },
      { name: 'A solo', value: 'R 584 / W 597', unit: 'MiB/s' },
    ],
  },
]

export const presets = {
  s4: {
    label: { zh: 'S4 排水態 [64:27:9:4]', en: 'S4 drain [64:27:9:4]' },
    disks: [
      { name: 'A', solo: 2064, w: 64 },
      { name: 'B', solo: 1522, w: 27 },
      { name: 'C', solo: 518, w: 9 },
      { name: 'D', solo: 220.3, w: 4 },
    ],
  },
  equal: {
    label: { zh: '等權 6:1:1:1', en: 'Equal 6:1:1:1' },
    disks: [
      { name: 'A', solo: 2064, w: 6 },
      { name: 'B', solo: 1522, w: 1 },
      { name: 'C', solo: 518, w: 1 },
      { name: 'D', solo: 220.3, w: 1 },
    ],
  },
  auto: {
    label: { zh: '自動加權 56:11:14:6', en: 'Auto-weight 56:11:14:6' },
    disks: [
      { name: 'A', solo: 2056, w: 56 },
      { name: 'B', solo: 1522, w: 11 },
      { name: 'C', solo: 518, w: 14 },
      { name: 'D', solo: 220.3, w: 6 },
    ],
  },
}
