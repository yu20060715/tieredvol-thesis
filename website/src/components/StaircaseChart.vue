<script setup>
import { ref, onMounted, onBeforeUnmount, computed } from 'vue'
import { staircase, staircaseConfigs } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)
const el = ref(null)
let chart = null

onMounted(async () => {
  const echarts = await import('echarts')
  chart = echarts.init(el.value)
  const steps = staircase.map((v, i) => (i === 0 ? v : v - staircase[i - 1]))
  chart.setOption({
    tooltip: {
      trigger: 'axis',
      formatter: params => {
        const p = params[0]
        const delta = p.dataIndex === 0 ? '' : (L.value === 'en'
          ? ` (+${steps[p.dataIndex]} vs previous)`
          : `（較前組 +${steps[p.dataIndex]}）`)
        return `${L.value === 'en' ? 'Config' : '組態'} ${staircaseConfigs[p.dataIndex]}: <b>${p.value} MB/s</b>${delta}`
      },
    },
    grid: { left: 60, right: 24, top: 40, bottom: 44 },
    xAxis: {
      type: 'category',
      data: staircaseConfigs,
      name: L.value === 'en' ? 'Auto-weight config' : '自動加權組態',
      nameLocation: 'middle',
      nameGap: 28,
    },
    yAxis: { type: 'value', name: 'MB/s', min: 1800 },
    series: [
      {
        type: 'bar',
        data: staircase,
        barWidth: '42%',
        label: { show: true, position: 'top', fontWeight: 600 },
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
          color: p => ['#007acc', '#3f7fbf', '#5f9fbf', '#7fb8cc'][p.dataIndex],
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
    <p class="tw-note" v-if="L === 'en'">Write throughput rises monotonically with each auto-weight config: 2078 → 2410 → 2896 → 3006 MB/s (§6.3.4).</p>
    <p class="tw-note" v-else>寫入吞吐隨自動加權組態單調上升：2078 → 2410 → 2896 → 3006 MB/s（§6.3.4）。</p>
  </div>
</template>

<style scoped>
.chart { height: 340px; width: 100%; }
.tw-note { font-size: 0.8rem; color: #666; margin-top: 0.25rem; }
</style>
