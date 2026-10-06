// 파일 이름 → Prism 문법 이름. 묶음(vendor/prism.js)에 들어 있는 언어만 적는다.
// 언어를 늘리려면 tools/build-prism.sh 의 LANGUAGES 와 이 표를 함께 고친다.
const BY_EXTENSION: Record<string, string> = {
  md: 'markdown', markdown: 'markdown',
  py: 'python',
  js: 'javascript', mjs: 'javascript', cjs: 'javascript', jsx: 'jsx',
  ts: 'typescript', tsx: 'tsx',
  sh: 'bash', bash: 'bash',
  json: 'json', jsonl: 'json',
  yml: 'yaml', yaml: 'yaml', toml: 'toml', ini: 'ini', conf: 'ini',
  // 마크업 문법이 <script>·<style> 안을 JS·CSS 로 나눈다. vue 는 거기에 바인딩 규칙을 더한 문법(grammars.ts).
  vue: 'vue',
  svelte: 'markup-plain', html: 'markup-plain', htm: 'markup-plain', xml: 'markup-plain', svg: 'markup-plain',
  css: 'css', scss: 'scss',
  sql: 'sql', go: 'go', rs: 'rust', java: 'java', rb: 'ruby',
  diff: 'diff', patch: 'diff',
}
const BY_NAME: Record<string, string> = { Dockerfile: 'docker' }

// 문법 이름. 모르는 파일이면 null(색 없이 그린다).
export const grammarOf = (path: string): string | null => {
  const name = path.split('/').at(-1) ?? ''
  const extension = name.includes('.') ? (name.split('.').at(-1) ?? '').toLowerCase() : ''

  return BY_NAME[name] ?? BY_EXTENSION[extension] ?? null
}
