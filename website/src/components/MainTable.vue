<script setup>
import { ref, computed } from 'vue'
import { mainTable, protocolLabels } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)

const sortKey = ref('write')
const sortDir = ref(-1)
const protocolFilter = ref('all')

const protocols = computed(() => [...new Set(mainTable.map(r => r.protocol))])

const rows = computed(() => {
  let r = mainTable
  if (protocolFilter.value !== 'all') r = r.filter(x => x.protocol === protocolFilter.value)
  return [...r].sort((a, b) => {
    const av = a[sortKey.value]
    const bv = b[sortKey.value]
    if (av === bv) return 0
    return (av > bv ? 1 : -1) * sortDir.value
  })
})

function setSort(key) {
  if (sortKey.value === key) sortDir.value *= -1
  else { sortKey.value = key; sortDir.value = -1 }
}

function arrow(key) {
  if (sortKey.value !== key) return '⇅'
  return sortDir.value === -1 ? '▼' : '▲'
}
</script>

<template>
  <div class="tw-table">
    <div class="tw-toolbar">
      <span class="tw-label">{{ L === 'en' ? 'Protocol' : '協定' }}</span>
      <select v-model="protocolFilter" class="tw-select">
        <option v-for="p in ['all', ...protocols]" :key="p" :value="p">{{ protocolLabels[p][L] }}</option>
      </select>
    </div>
    <table>
      <thead>
        <tr>
          <th>{{ L === 'en' ? 'Volume' : '卷' }}</th>
          <th>{{ L === 'en' ? 'Disks' : '碟數' }}</th>
          <th>{{ L === 'en' ? 'Weight' : '權重' }}</th>
          <th class="sortable" @click="setSort('write')">{{ L === 'en' ? 'Write (MB/s)' : '寫入 (MB/s)' }} {{ arrow('write') }}</th>
          <th class="sortable" @click="setSort('read')">{{ L === 'en' ? 'Read (MB/s)' : '讀取 (MB/s)' }} {{ arrow('read') }}</th>
          <th>{{ L === 'en' ? 'Protocol' : '協定' }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.name">
          <td><strong>{{ r.name }}</strong></td>
          <td>{{ r.disks }}</td>
          <td><code>{{ r.weight }}</code></td>
          <td>{{ r.write }}</td>
          <td>{{ r.read }}</td>
          <td>{{ r.protocol }}</td>
        </tr>
      </tbody>
    </table>
    <p class="tw-note" v-if="L === 'en'">Click “Write / Read” headers to sort. From thesis Table 6.1 (libaio, 256K sequential, QD=32).</p>
    <p class="tw-note" v-else>點擊「寫入 / 讀取」標題可排序。數據取自論文表 6.1（libaio，256K 順序 I/O，QD=32）。</p>
  </div>
</template>

<style scoped>
.tw-table { margin: 0.75rem 0; }
.tw-toolbar { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.6rem; }
.tw-label { font-size: 0.875rem; color: #666; }
.tw-select {
  padding: 0.25rem 0.5rem; border-radius: 4px;
  border: 1px solid #ccc; background: #fff; color: #333; font-size: 0.875rem;
}
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid #ddd; }
thead th { background: #f0f0f0; font-weight: 600; white-space: nowrap; }
th.sortable { cursor: pointer; user-select: none; }
th.sortable:hover { color: #007acc; }
tr:hover td { background: #fafafa; }
code { background: #f0f0f0; padding: 0.1rem 0.35rem; border-radius: 4px; }
.tw-note { font-size: 0.8rem; color: #666; margin-top: 0.5rem; }
</style>
