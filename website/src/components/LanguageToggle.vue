<script setup>
import { useRoute, useRouter } from 'vue-router'
import { useLangStore } from '../stores/lang'

const store = useLangStore()
const route = useRoute()
const router = useRouter()

function switchLang(l) {
  store.setLang(l)
  const page = route.params.page || 'home'
  router.push(`/${l}/${page}`)
}
</script>

<template>
  <div class="lang-toggle">
    <button :class="{ active: store.lang.value === 'en' }" @click="switchLang('en')">
      EN
    </button>
    <button :class="{ active: store.lang.value === 'zh' }" @click="switchLang('zh')">
      中文
    </button>
  </div>
</template>

<style scoped>
.lang-toggle {
  text-align: right;
  margin-bottom: 0.5rem;
}
.lang-toggle button {
  background: none;
  border: 1px solid #ccc;
  padding: 0.3rem 0.7rem;
  cursor: pointer;
  font-size: 0.85rem;
}
.lang-toggle button:first-child { border-radius: 4px 0 0 4px; }
.lang-toggle button:last-child { border-radius: 0 4px 4px 0; margin-left: -1px; }
.lang-toggle button.active {
  background: #007acc;
  color: #fff;
  border-color: #007acc;
}
</style>
