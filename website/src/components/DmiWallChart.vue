<script setup>
import { ref, onMounted, onBeforeUnmount, computed } from 'vue'
import { dmi } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)
const el = ref(null)
let chart = null

onMounted(async () => {
  const echarts = await import('echarts')
  chart = echarts.init(el.value)
  const xLabels = L.value === 'en'
    ? ['Proportional [64:47:16]', 'DMI-aware [64:30:10]']
    : ['比例權重 [64:47:16]', 'DMI-aware 權重 [64:30:10]']
  const modelLabel = L.value === 'en' ? 'Model 3364 (S3_max)' : '模型預測 3364（S3_max）'
  const budgetLabel = L.value === 'en' ? 'Shared-bus ceiling 1300' : '共享匯流排上限 1300'
  chart.setOption({
    tooltip: { trigger: 'axis' },
    grid: { left: 60, right: 24, top: 40, bottom: 44 },
    xAxis: { type: 'category', data: xLabels },
    yAxis: { type: 'value', name: 'MB/s', min: 2000 },
    series: [
      {
        type: 'bar',
        data: [dmi.proportional, dmi.aware],
        barWidth: '38%',
        label: { show: true, position: 'top', fontWeight: 600, formatter: '{c} MB/s' },
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
          color: p => (p.dataIndex === 0 ? '#9aa7b5' : '#10b981'),
        },
        markLine: {
          symbol: 'none',
          label: { formatter: '{b}', position: 'insideEndTop', fontWeight: 600, color: '#f59e0b' },
          data: [
            { yAxis: dmi.model, name: modelLabel },
            { yAxis: dmi.budget, name: budgetLabel },
          ],
          lineStyle: { type: 'dashed', color: '#f59e0b' },
        },
      },
    ],
  })
})

onBeforeUnmount(() => { if (chart) chart.dispose() })
</script>

<template>
  <div class="tw-chart">
    <div ref="el" class="chart"></div>
    <p class="tw-note" v-if="L === 'en'">DMI-aware weights lift throughput +32% over proportional (2561 → 3370 MB/s), approaching the model ceiling 3364 MB/s (§6.4.1, Fig. F11).</p>
    <p class="tw-note" v-else>DMI-aware 權重較比例權重提升 +32%（2561 → 3370 MB/s），逼近模型預測上限 3364 MB/s（§6.4.1、圖 F11）。</p>
  </div>
</template>

<style scoped>
.chart { height: 340px; width: 100%; }
.tw-note { font-size: 0.8rem; color: #666; margin-top: 0.25rem; }
</style>
