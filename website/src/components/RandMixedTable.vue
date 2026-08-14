<script setup>
import { computed } from 'vue'
import { randMixed } from '../data.js'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const L = computed(() => store.lang.value)
</script>

<template>
  <div class="tw-mixed">
    <div v-for="(t, i) in randMixed" :key="i" class="tw-block">
      <h4>{{ t.title[L] }}</h4>
      <table>
        <thead><tr><th v-if="L === 'en'">Volume</th><th v-else>卷</th><th v-if="L === 'en'">Result</th><th v-else>結果</th></tr></thead>
        <tbody>
          <tr v-for="(r, j) in t.rows" :key="j">
            <td>{{ r.name }}</td>
            <td><code>{{ r.value }} {{ r.unit }}</code></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.tw-mixed { display: flex; gap: 1rem; flex-wrap: wrap; margin: 0.75rem 0; }
.tw-block { flex: 1; min-width: 220px; }
h4 { margin: 0 0 0.4rem; font-size: 0.95rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.875rem; }
th, td { padding: 0.45rem 0.7rem; text-align: left; border-bottom: 1px solid #ddd; }
thead th { background: #f0f0f0; font-weight: 600; }
tr:hover td { background: #fafafa; }
code { background: #f0f0f0; padding: 0.1rem 0.35rem; border-radius: 4px; }
</style>
