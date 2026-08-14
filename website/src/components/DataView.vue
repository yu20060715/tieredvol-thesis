<script setup>
import { computed } from 'vue'
import { useLangStore } from '../stores/lang'
import MainTable from './MainTable.vue'
import StaircaseChart from './StaircaseChart.vue'
import DmiWallChart from './DmiWallChart.vue'
import LvmCompareChart from './LvmCompareChart.vue'
import AutoWeightTable from './AutoWeightTable.vue'
import RandMixedTable from './RandMixedTable.vue'
import BottleneckCalc from './BottleneckCalc.vue'

const store = useLangStore()
const L = computed(() => store.lang.value)
</script>

<template>
  <div class="dataview">
    <h1 v-if="L === 'zh'">互動數據展示</h1>
    <h1 v-else>Interactive Data</h1>
    <p class="note" v-if="L === 'zh'">全部數字取自論文第六章實驗評估，與 <code>RESULTS.md</code> 一致。</p>
    <p class="note" v-else>All figures come from Chapter 6 (Experimental Evaluation) and are consistent with <code>RESULTS.md</code>.</p>

    <h2 id="main" v-if="L === 'zh'">主表</h2>
    <h2 id="main" v-else>Main table</h2>
    <MainTable />

    <h2 id="staircase" v-if="L === 'zh'">自動加權階梯</h2>
    <h2 id="staircase" v-else>Auto-weight staircase</h2>
    <StaircaseChart />
    <AutoWeightTable />

    <h2 id="dmi" v-if="L === 'zh'">DMI 牆</h2>
    <h2 id="dmi" v-else>DMI wall</h2>
    <DmiWallChart />

    <h2 id="lvm" v-if="L === 'zh'">vs LVM</h2>
    <h2 id="lvm" v-else>vs LVM</h2>
    <LvmCompareChart />

    <h2 id="random" v-if="L === 'zh'">隨機與混寫</h2>
    <h2 id="random" v-else>Random and mixed workloads</h2>
    <RandMixedTable />

    <h2 id="calc" v-if="L === 'zh'">瓶頸模型計算器</h2>
    <h2 id="calc" v-else>Bottleneck model calculator</h2>
    <BottleneckCalc />
  </div>
</template>

<style scoped>
.dataview { padding-top: 0.25rem; }
.dataview h1 { font-size: 1.6rem; }
.dataview h2 { margin: 1.75rem 0 0.5rem; border-bottom: 1px solid #ddd; padding-bottom: 0.25rem; }
.note { color: #555; font-size: 0.9rem; margin: 0.25rem 0 0.75rem; }
code { background: #f0f0f0; padding: 0.1rem 0.35rem; border-radius: 4px; font-size: 0.9em; }
</style>
