import { ref } from 'vue'

export const lang = ref('en')

export function useLangStore() {
  function setLang(l) {
    lang.value = l
  }
  return { lang, setLang }
}
