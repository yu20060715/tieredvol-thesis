<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const route = useRoute()

const props = defineProps({ headings: { type: Array, default: () => [] } })
const emit = defineEmits(['navigate'])

const L = computed(() => store.lang.value)

const groups = computed(() => [
  {
    title: L.value === 'en' ? 'General' : '總覽',
    items: [{ id: 'home', titleZh: '首頁', titleEn: 'Home' }],
  },
  {
    title: L.value === 'en' ? 'Chapters' : '章節',
    items: [
      { id: '00-front', titleZh: '前頁：摘要・符號・縮寫', titleEn: 'Front Matter' },
      { id: 'ch01', titleZh: '第一章 緒論', titleEn: '1 Introduction' },
      { id: 'ch02', titleZh: '第二章 背景與相關研究', titleEn: '2 Background and Related Work' },
      { id: 'ch03', titleZh: '第三章 系統設計（一）核心機制', titleEn: '3 System Design (I) Core Mechanisms' },
      { id: 'ch04', titleZh: '第四章 系統設計（二）進階機制與容錯', titleEn: '4 System Design (II) Advanced and Fault Tolerance' },
      { id: 'ch05', titleZh: '第五章 實作', titleEn: '5 Implementation' },
      { id: 'ch06', titleZh: '第六章 實驗評估', titleEn: '6 Experimental Evaluation' },
      { id: 'ch07', titleZh: '第七章 結論與貢獻總結', titleEn: '7 Conclusion and Contributions' },
    ],
  },
  {
    title: L.value === 'en' ? 'Appendices' : '附錄',
    items: [
      { id: 'appendix-a', titleZh: '附錄 A 量測協定與配置', titleEn: 'A Measurement Protocols' },
      { id: 'appendix-b', titleZh: '附錄 B 失敗與修正紀錄', titleEn: 'B Failure and Correction Log' },
    ],
  },
  {
    title: L.value === 'en' ? 'Interactive Data' : '互動數據',
    items: [{ id: 'data', titleZh: '圖表與計算器', titleEn: 'Charts & Calculator' }],
  },
  {
    title: L.value === 'en' ? 'Project Docs (DRIVER)' : '專案文件（DRIVER）',
    items: [
      { id: 'overview', titleZh: '總覽 / README', titleEn: 'Overview / README' },
      { id: 'ARCHITECTURE', titleZh: '架構', titleEn: 'Architecture' },
      { id: 'DESIGN', titleZh: '設計', titleEn: 'Design' },
      { id: 'CONFIG', titleZh: '配置格式', titleEn: 'Config format' },
      { id: 'MAPPING', titleZh: '映射機制', titleEn: 'Mapping' },
      { id: 'RESULTS', titleZh: '實驗結果', titleEn: 'Results' },
      { id: 'TEST_PLAN', titleZh: '測試計畫', titleEn: 'Test plan' },
      { id: 'WC', titleZh: '寫入合併（WC）', titleEn: 'Write coalescing' },
      { id: 'MIRROR', titleZh: '同步鏡像', titleEn: 'Mirror' },
      { id: 'PARTITION_SPLITTING', titleZh: '分區拆分', titleEn: 'Partition splitting' },
      { id: 'KERNEL_TESTS', titleZh: '核心測試', titleEn: 'Kernel tests' },
      { id: 'ROADMAP', titleZh: '路線圖', titleEn: 'Roadmap' },
      { id: 'SUPPLEMENTARY', titleZh: '補充資料', titleEn: 'Supplementary' },
    ],
  },
])

function titleOf(item) {
  return L.value === 'en' ? item.titleEn : item.titleZh
}

function isActive(id) {
  return route.params.page === id
}

function scrollTo(anchor) {
  const el = document.getElementById(anchor)
  if (el) el.scrollIntoView({ behavior: 'smooth' })
  emit('navigate')
}
</script>

<template>
  <nav class="sidebar-nav">
    <div v-for="g in groups" :key="g.title">
      <h3>{{ g.title }}</h3>
      <ul>
        <li v-for="it in g.items" :key="it.id">
          <router-link
            :to="`/${store.lang.value}/${it.id}`"
            :class="{ active: isActive(it.id) }"
          >
            {{ titleOf(it) }}
          </router-link>
        </li>
      </ul>
    </div>
    <div v-if="headings.length" class="page-toc">
      <h4>{{ L === 'en' ? 'On this page' : '本頁目錄' }}</h4>
      <ul>
        <li v-for="h in headings" :key="h.anchor" :style="{ paddingLeft: (h.level - 1) * 1 + 'rem' }">
          <a :href="`#${h.anchor}`" @click.prevent="scrollTo(h.anchor)">{{ h.text }}</a>
        </li>
      </ul>
    </div>
  </nav>
</template>

<style scoped>
.sidebar-nav h3 {
  margin: 1rem 0 0.5rem;
  font-size: 0.9rem;
  color: #666;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.sidebar-nav h4 {
  margin: 1rem 0 0.25rem;
  font-size: 0.8rem;
  color: #888;
}
.sidebar-nav ul { list-style: none; padding: 0; margin: 0; }
.sidebar-nav li { margin: 0.25rem 0; }
.sidebar-nav a {
  color: #333;
  text-decoration: none;
  font-size: 0.9rem;
  display: block;
  padding: 0.2rem 0.4rem;
  border-radius: 4px;
}
.sidebar-nav a:hover { background: #e0e0e0; }
.sidebar-nav a.active { background: #007acc; color: #fff; }
.page-toc { margin-top: 1.5rem; border-top: 1px solid #ddd; padding-top: 0.5rem; }
.page-toc a { font-size: 0.8rem; color: #555; }
</style>
