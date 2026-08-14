import MarkdownIt from 'markdown-it'

const BASE = import.meta.env.BASE_URL

const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: true,
})

export function slugify(text) {
  return text
    .toLowerCase()
    .replace(/[^\w\u4e00-\u9fff]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

md.renderer.rules.heading_open = (tokens, i, options, env, self) => {
  const text = tokens[i + 1].content
  tokens[i].attrSet('id', slugify(text))
  return self.renderToken(tokens, i, options)
}

export function renderMarkdown(text) {
  let html = md.render(text)
  html = html.replace(/src="figs\//g, `src="${BASE}figs/`)
  return html
}

export function extractHeadings(text) {
  const headings = []
  const re = /^#{1,3}\s+(.+)$/gm
  let m
  while ((m = re.exec(text)) !== null) {
    headings.push({
      level: m[0].trim().indexOf(' '),
      text: m[1],
      anchor: slugify(m[1]),
    })
  }
  return headings
}
