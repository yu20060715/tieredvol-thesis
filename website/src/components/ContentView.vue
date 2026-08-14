<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { renderMarkdown, extractHeadings } from '../utils/markdown'
import HomeView from './HomeView.vue'
import DataView from './DataView.vue'

const emit = defineEmits(['headings'])
const route = useRoute()
const rendered = ref('')

const modules = import.meta.glob('../content/**/*.md', { query: '?raw', import: 'default' })

const pages = [
  '00-front', 'ch01', 'ch02', 'ch03', 'ch04', 'ch05', 'ch06', 'ch07',
  'appendix-a', 'appendix-b',
]
const driverDocs = [
  'overview', 'ARCHITECTURE', 'CONFIG', 'DESIGN', 'KERNEL_TESTS', 'MAPPING',
  'MIRROR', 'PARTITION_SPLITTING', 'RESULTS', 'ROADMAP', 'SUPPLEMENTARY', 'TEST_PLAN', 'WC',
]

const page = computed(() => route.params.page || 'home')

async function load() {
  const lang = route.params.lang || 'zh'
  const p = route.params.page || 'home'
  if (p === 'home' || p === 'data') {
    rendered.value = ''
    emit('headings', [])
    return
  }
  let file
  if (driverDocs.includes(p)) file = `driver/${p}.md`
  else if (pages.includes(p)) file = `${lang}/chapters/${p}.md`
  else {
    rendered.value = '<p>Page not found.</p>'
    emit('headings', [])
    return
  }
  const key = `../content/${file}`
  const loader = modules[key]
  if (!loader) {
    rendered.value = '<p>Content not found for this language.</p>'
    emit('headings', [])
    return
  }
  const raw = (await loader()).replace(/\r\n/g, '\n')
  rendered.value = renderMarkdown(raw)
  emit('headings', extractHeadings(raw))
}

watch(() => [route.params.lang, route.params.page], load, { immediate: true })
</script>

<template>
  <HomeView v-if="page === 'home'" />
  <DataView v-else-if="page === 'data'" />
  <!-- eslint-disable-next-line vue/no-v-html -->
  <div v-else class="content" v-html="rendered" />
</template>

<style>
.content { line-height: 1.7; }
.content h1, .content h2, .content h3 { margin-top: 1.5em; margin-bottom: 0.5em; }
.content h1 { font-size: 1.6rem; }
.content h2 { font-size: 1.3rem; }
.content h3 { font-size: 1.1rem; }
.content p { margin: 0.7em 0; }
.content ul, .content ol { padding-left: 1.5rem; margin: 0.5em 0; }
.content pre {
  background: #f0f0f0;
  padding: 0.8rem;
  border-radius: 4px;
  overflow-x: auto;
}
.content code { font-size: 0.9em; }
.content table { border-collapse: collapse; width: 100%; margin: 1em 0; }
.content th, .content td { border: 1px solid #ccc; padding: 0.4rem 0.6rem; text-align: left; }
.content th { background: #f0f0f0; }
.content img { max-width: 100%; }
.content blockquote {
  border-left: 4px solid #007acc;
  margin: 1em 0;
  padding: 0.2em 1em;
  color: #555;
}
.content hr { border: none; border-top: 1px solid #ddd; margin: 1.5em 0; }
.content .katex, .content .mermaid { background: none; }
</style>
