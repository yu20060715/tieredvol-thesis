<script setup>
import { computed } from 'vue'
import { autoWeight } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)
</script>

<template>
  <div class="tw-table">
    <table>
      <thead>
        <tr>
          <th v-if="L === 'en'">Config</th><th v-else>組態</th>
          <th>auto_weight</th>
          <th v-if="L === 'en'">Model (MB/s)</th><th v-else>模型預測 (MB/s)</th>
          <th v-if="L === 'en'">Measured (MB/s)</th><th v-else>實測 (MB/s)</th>
          <th v-if="L === 'en'">Error</th><th v-else>誤差</th>
          <th v-if="L === 'en'">Utilization</th><th v-else>輸出利用率</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in autoWeight" :key="r.config">
          <td><strong>{{ r.config }}</strong></td>
          <td><code>{{ r.weight }}</code></td>
          <td>{{ r.model }}</td>
          <td>{{ r.measured }}</td>
          <td :class="{ neg: r.deviation < 0 }">{{ r.deviation }}%</td>
          <td>{{ r.util }}%</td>
        </tr>
      </tbody>
    </table>
    <p class="tw-note" v-if="L === 'en'">auto_weight finds near-optimal weights within ±6% model error; output utilization reaches 93.7%–97.6% (§6.3.2).</p>
    <p class="tw-note" v-else>auto_weight 以模型命中誤差 ±6% 內求得近最優權重，輸出利用率達 93.7%–97.6%（§6.3.2）。</p>
  </div>
</template>

<style scoped>
.tw-table { margin: 0.75rem 0; }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid #ddd; }
thead th { background: #f0f0f0; font-weight: 600; }
tr:hover td { background: #fafafa; }
code { background: #f0f0f0; padding: 0.1rem 0.35rem; border-radius: 4px; }
.neg { color: #c62828; }
.tw-note { font-size: 0.8rem; color: #666; margin-top: 0.5rem; }
</style>
