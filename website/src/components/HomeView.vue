<script setup>
import { computed } from 'vue'
import { useLangStore } from '../stores/lang'

const BASE = import.meta.env.BASE_URL
const store = useLangStore()
const L = computed(() => store.lang.value)
</script>

<template>
  <div class="home">
    <h1>TieredVol</h1>
    <p class="sub" v-if="L === 'zh'">異質磁碟之加權條帶化（Linux Device Mapper 核心目標）</p>
    <p class="sub" v-else>Weighted striping of heterogeneous disks — a Linux Device Mapper kernel target</p>

    <img class="arch" :src="BASE + (L === 'en' ? 'figs/F3_architecture_en.svg' : 'figs/F3_architecture.svg')" alt="TieredVol architecture" />

    <h2 v-if="L === 'zh'">三大硬體洞見</h2>
    <h2 v-else>Three hardware insights</h2>
    <ul v-if="L === 'zh'">
      <li><strong>插槽（slot）決定速率</strong>：B 碟由 PCIe 2.0 x1 移至 3.0 x4，寫入 413 → 1522 MB/s（3.7×）。</li>
      <li><strong>共享匯流排（DMI）牆</strong>：B/C/D 同走 PCH DMI，三碟併寫封頂 ~1300 MB/s；DMI-aware 權重把瓶頸還給 A，達 3370 MB/s。</li>
      <li><strong>SLC 假象</strong>：B/C/D 為 TLC 碟，寫入快取模擬 SLC 速度——「快於規格」來自控制器 SLC 快取。</li>
    </ul>
    <ul v-else>
      <li><strong>The slot decides the speed</strong>: Moving disk B from PCIe 2.0 x1 to 3.0 x4 raised write throughput 413 → 1522 MB/s (3.7×).</li>
      <li><strong>The shared-bus (DMI) wall</strong>: B/C/D share the PCH DMI; three-disk writes cap at ~1300 MB/s. DMI-aware weights return the bottleneck to A, reaching 3370 MB/s.</li>
      <li><strong>The SLC illusion</strong>: B/C/D are TLC drives whose write caches emulate SLC speed — “faster than spec” comes from the controller’s SLC cache.</li>
    </ul>

    <h2 v-if="L === 'zh'">核心結果（S4 排水態，4 碟）</h2>
    <h2 v-else>Key results (S4 drain state, 4 disks)</h2>
    <table>
      <thead><tr><th v-if="L === 'zh'">指標</th><th v-else>Metric</th><th>Value</th></tr></thead>
      <tbody>
        <tr><td v-if="L === 'zh'">加權條帶化寫入</td><td v-else>Weighted-stripe write</td><td><b>3300 MB/s</b></td></tr>
        <tr><td v-if="L === 'zh'">加權條帶化讀取</td><td v-else>Weighted-stripe read</td><td><b>4292 MB/s</b></td></tr>
        <tr><td v-if="L === 'zh'">vs LVM striped（256K）</td><td v-else>vs LVM striped (256K)</td><td v-if="L === 'zh'">寫入 <b>2.04×</b>、讀取 <b>2.40×</b></td><td v-else>write <b>2.04×</b>, read <b>2.40×</b></td></tr>
        <tr><td v-if="L === 'zh'">瓶頸模型誤差</td><td v-else>Bottleneck-model error</td><td>≤ 6%</td></tr>
      </tbody>
    </table>

    <p class="links">
      <router-link :to="`/${L}/ch01`" class="btn">{{ L === 'zh' ? '閱讀論文 →' : 'Read the thesis →' }}</router-link>
      <router-link :to="`/${L}/data`" class="btn">{{ L === 'zh' ? '互動數據 →' : 'Interactive data →' }}</router-link>
      <router-link :to="`/${L}/overview`" class="btn">{{ L === 'zh' ? '專案文件 →' : 'Project docs →' }}</router-link>
    </p>
  </div>
</template>

<style scoped>
.home { padding-top: 0.25rem; }
.home h1 { font-size: 2rem; }
.sub { color: #555; margin: 0.25rem 0 1rem; }
.arch { max-width: 100%; margin: 0.75rem 0 0.5rem; border: 1px solid #eee; }
.home h2 { margin-top: 1.5rem; }
.home ul { padding-left: 1.5rem; margin: 0.5rem 0; }
.home li { margin: 0.4rem 0; }
table { border-collapse: collapse; width: 100%; margin: 0.75em 0; }
th, td { border: 1px solid #ccc; padding: 0.4rem 0.6rem; text-align: left; }
th { background: #f0f0f0; }
.links { margin-top: 1.5rem; display: flex; gap: 0.75rem; flex-wrap: wrap; }
.btn {
  background: #007acc;
  color: #fff;
  text-decoration: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  font-size: 0.95rem;
}
.btn:hover { background: #005fa3; }
</style>
