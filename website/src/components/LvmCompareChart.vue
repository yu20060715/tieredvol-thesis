<script setup>
import { ref, onMounted, onBeforeUnmount, computed } from 'vue'
import { lvmCompare } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)
const el = ref(null)
let chart = null

onMounted(async () => {
  const echarts = await import('echarts')
  chart = echarts.init(el.value)
  const cold = L.value === 'en' ? 'TieredVol S4 (cold)' : 'TieredVol S4（冷態）'
  const drain = L.value === 'en' ? 'TieredVol S4 (drain)' : 'TieredVol S4（排水態）'
  chart.setOption({
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    legend: { data: ['LVM striped', cold, drain] },
    grid: { left: 60, right: 24, top: 44, bottom: 40 },
    xAxis: { type: 'category', data: L.value === 'en' ? ['Write', 'Read'] : ['寫入', '讀取'] },
    yAxis: { type: 'value', name: 'MB/s' },
    series: [
      {
        name: 'LVM striped',
        type: 'bar',
        data: [lvmCompare.lvm.write, lvmCompare.lvm.read],
        itemStyle: { color: '#9aa7b5', borderRadius: [4, 4, 0, 0] },
        label: { show: true, position: 'top' },
      },
      {
        name: cold,
        type: 'bar',
        data: [lvmCompare.tieredCold.write, lvmCompare.tieredCold.read],
        itemStyle: { color: '#60a5fa', borderRadius: [4, 4, 0, 0] },
        label: { show: true, position: 'top' },
      },
      {
        name: drain,
        type: 'bar',
        data: [lvmCompare.tieredDrain.write, lvmCompare.tieredDrain.read],
        itemStyle: { color: '#10b981', borderRadius: [4, 4, 0, 0] },
        label: { show: true, position: 'top' },
      },
    ],
  })
})

onBeforeUnmount(() => { if (chart) chart.dispose() })
</script>

<template>
  <div class="tw-chart">
    <div ref="el" class="chart"></div>
    <p class="tw-note" v-if="L === 'en'">Drain-state 4-disk volume reaches <b>2.04×/2.40×</b> of LVM striped in write/read; cold state 1.91×/2.00× (§6.4.3, Table 6.4).</p>
    <p class="tw-note" v-else>排水態 4 碟捲寫入/讀取達 LVM striped 的 <b>2.04×/2.40×</b>；冷態亦達 1.91×/2.00×（§6.4.3、表 6.4）。</p>
  </div>
</template>

<style scoped>
.chart { height: 340px; width: 100%; }
.tw-note { font-size: 0.8rem; color: #666; margin-top: 0.25rem; }
</style>
