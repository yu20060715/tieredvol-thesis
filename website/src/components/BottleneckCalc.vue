<script setup>
import { ref, reactive, computed } from 'vue'
import { presets } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)

const currentPreset = ref('s4')

const disks = reactive([
  { name: 'A', solo: 2064, w: 64 },
  { name: 'B', solo: 1522, w: 27 },
  { name: 'C', solo: 518, w: 9 },
  { name: 'D', solo: 220.3, w: 4 },
])

function applyPreset(key) {
  const p = presets[key]
  p.disks.forEach((d, i) => {
    if (disks[i]) {
      disks[i].name = d.name
      disks[i].solo = d.solo
      disks[i].w = d.w
    }
  })
}

const result = computed(() => {
  const sumW = disks.reduce((s, d) => s + (Number(d.w) || 0), 0)
  const loads = disks.map(d => {
    const w = Number(d.w) || 0
    const solo = Number(d.solo) || 0
    const share = sumW ? w / sumW : 0
    const load = w > 0 && solo > 0 ? (solo * sumW) / w : Infinity
    return { ...d, share, load }
  })
  const T = Math.min(...loads.map(l => l.load))
  const bottleneck = loads.filter(l => Math.abs(l.load - T) < 1e-6).map(l => l.name)
  return { sumW, loads, T, bottleneck }
})

const fmt = n => (Number.isInteger(n) ? n : n.toFixed(1))
</script>

<template>
  <div class="tw-calc">
    <div class="tw-controls">
      <span class="tw-label">{{ L === 'en' ? 'Preset' : '預設組態' }}</span>
      <select v-model="currentPreset" class="tw-select" @change="applyPreset(currentPreset)">
        <option v-for="(p, key) in presets" :key="key" :value="key">{{ p.label[L] }}</option>
      </select>
    </div>
    <table>
      <thead>
        <tr>
          <th v-if="L === 'en'">Disk</th><th v-else>碟</th>
          <th v-if="L === 'en'">solo (MB/s)</th><th v-else>solo (MB/s)</th>
          <th v-if="L === 'en'">Weight w</th><th v-else>權重 w</th>
          <th v-if="L === 'en'">Share w/ΣW</th><th v-else>份額 w/ΣW</th>
          <th v-if="L === 'en'">Model load</th><th v-else>模型負載</th>
          <th v-if="L === 'en'">Bottleneck</th><th v-else>瓶頸</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(d, i) in result.loads" :key="d.name"
            :class="{ bottleneck: result.bottleneck.includes(d.name) }">
          <td><strong>{{ d.name }}</strong></td>
          <td><input v-model.number="disks[i].solo" type="number" step="0.1" min="0" class="tw-input" /></td>
          <td><input v-model.number="disks[i].w" type="number" step="1" min="0" class="tw-input" /></td>
          <td>{{ (d.share * 100).toFixed(1) }}%</td>
          <td>{{ d.load === Infinity ? '—' : fmt(d.load) }}</td>
          <td>
            <span v-if="result.bottleneck.includes(d.name)" class="tw-tag">{{ L === 'en' ? 'bottleneck' : '瓶頸' }}</span>
            <span v-else>—</span>
          </td>
        </tr>
      </tbody>
    </table>
    <div class="tw-result">
      <code>T(W) = min(soloᵢ × ΣW / wᵢ)</code>
      <span class="tw-formula">ΣW = {{ result.sumW }}</span>
      <span class="tw-answer"><span v-if="L === 'en'">Predicted T(W) =</span><span v-else>預測總吞吐 T(W) =</span> <b>{{ fmt(result.T) }} MB/s</b></span>
      <span class="tw-answer"><span v-if="L === 'en'">Bottleneck:</span><span v-else>瓶頸碟：</span> <b>{{ result.bottleneck.join(', ') }}</b></span>
    </div>
    <p class="tw-note" v-if="L === 'en'">Edit any solo rate or weight to recompute live. When model loads converge, total throughput approaches the sum of per-disk solo rates (§3.2, §6.3.2).</p>
    <p class="tw-note" v-else>改任一碟的 solo 或權重即時重算。調整權重使各碟「模型負載」趨於一致時，總吞吐接近各碟 solo 之和（§3.2、§6.3.2）。</p>
  </div>
</template>

<style scoped>
.tw-calc { margin: 0.75rem 0; }
.tw-controls { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.6rem; }
.tw-label { font-size: 0.875rem; color: #666; }
.tw-select, .tw-input {
  padding: 0.25rem 0.5rem; border-radius: 4px;
  border: 1px solid #ccc; background: #fff; color: #333; font-size: 0.875rem;
}
.tw-input { width: 6rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td { padding: 0.45rem 0.7rem; text-align: left; border-bottom: 1px solid #ddd; }
thead th { background: #f0f0f0; font-weight: 600; }
tr:hover td { background: #fafafa; }
tr.bottleneck td { background: #eef4fb; }
.tw-tag {
  background: #007acc; color: #fff; font-size: 0.75rem;
  padding: 0.1rem 0.5rem; border-radius: 999px; font-weight: 600;
}
.tw-result {
  margin-top: 0.75rem; padding: 0.6rem 0.85rem; border-radius: 4px;
  background: #f0f0f0; border: 1px solid #ddd;
  display: flex; gap: 1rem; flex-wrap: wrap; align-items: baseline; font-size: 0.9rem;
}
.tw-formula { color: #666; }
.tw-answer b { color: #007acc; }
.tw-note { font-size: 0.8rem; color: #666; margin-top: 0.5rem; }
</style>
