import { createRouter, createWebHashHistory } from 'vue-router'

const routes = [
  { path: '/', redirect: '/en/home' },
  {
    path: '/:lang(en|zh)?/:page(.*)?',
    component: () => import('../components/ContentView.vue'),
  },
  { path: '/:pathMatch(.*)*', redirect: '/en/home' },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

export default router
