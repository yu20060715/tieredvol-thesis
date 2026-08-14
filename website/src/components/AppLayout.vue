<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import Sidebar from './Sidebar.vue'
import LanguageToggle from './LanguageToggle.vue'
import { useLangStore } from '../stores/lang'

const route = useRoute()
const store = useLangStore()

watch(
  () => route.params.lang,
  (l) => { if (l) store.setLang(l) },
  { immediate: true }
)

const collapsed = ref(false)
const headings = ref([])
function onNav() {
  collapsed.value = true
}
</script>

<template>
  <div class="app-layout">
    <aside class="sidebar" :class="{ collapsed }">
      <button
        class="toggle-btn"
        :title="collapsed ? 'Open sidebar' : 'Close sidebar'"
        @click="collapsed = !collapsed"
      >
        {{ collapsed ? '☰' : '✕' }}
      </button>
      <div v-show="!collapsed">
        <Sidebar :headings="headings" @navigate="onNav" />
      </div>
    </aside>
    <main class="content-area">
      <LanguageToggle />
      <router-view :key="route.fullPath" @headings="h => headings = h" />
    </main>
  </div>
</template>

<style scoped>
.app-layout {
  display: flex;
  min-height: 100vh;
}
.sidebar {
  width: 260px;
  background: #f5f5f5;
  border-right: 1px solid #ddd;
  padding: 1rem;
  transition: width 0.2s, padding 0.2s;
  overflow-y: auto;
  flex-shrink: 0;
}
.sidebar.collapsed {
  width: 40px;
  padding: 0.5rem;
}
.toggle-btn {
  background: none;
  border: 1px solid #ccc;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1rem;
  padding: 0.25rem 0.5rem;
  width: 100%;
}
.content-area {
  flex: 1;
  padding: 1.5rem 2rem;
  max-width: 960px;
  overflow-y: auto;
}

@media (max-width: 768px) {
  .sidebar {
    width: 220px;
    padding: 0.75rem;
  }
  .sidebar.collapsed {
    width: 36px;
    padding: 0.4rem;
  }
  .content-area {
    padding: 1rem;
  }
}

@media (max-width: 480px) {
  .sidebar:not(.collapsed) {
    position: fixed;
    top: 0;
    left: 0;
    bottom: 0;
    z-index: 100;
    width: 260px;
    box-shadow: 2px 0 8px rgba(0, 0, 0, 0.15);
  }
  .sidebar.collapsed {
    width: 0;
    padding: 0;
    overflow: hidden;
    border: none;
  }
  .sidebar.collapsed .toggle-btn {
    position: fixed;
    top: 0.5rem;
    left: 0.5rem;
    width: auto;
    z-index: 101;
    padding: 0.3rem 0.6rem;
    font-size: 1.2rem;
  }
  .content-area {
    padding: 0.75rem;
  }
}
</style>
