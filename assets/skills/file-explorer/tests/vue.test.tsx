import { expect, test } from 'claude-code/testing'

import { highlightLines } from '../hooks/highlight'
import type { Token } from '../hooks/highlight'
import { grammarOf } from '../hooks/languages'

const LIMIT = 90000
const SOURCE = '<template>\n  <p :class="cn(\'a\', props.x)" title="plain">{{ count + 1 }}</p>\n</template>\n'
// 글자 → 그 조각의 종류 목록(바깥에서 안쪽)
// 앞뒤 공백은 떼고 비교한다(색 없는 글자는 옆의 공백과 한 조각으로 온다).
const kindsOf = (line: readonly Token[] = [], text: string) => line.find(token => token.text.trim() === text)?.kinds ?? null

test('vue 는 전용 문법으로, html·svelte 는 바인딩 규칙이 없는 마크업으로 고른다', () => {
  expect(grammarOf('src/App.vue')).toBe('vue')
  expect(grammarOf('public/index.html')).toBe('markup-plain')
  expect(grammarOf('src/Card.svelte')).toBe('markup-plain')
})

test('vue: 바인딩 속성(:class)의 따옴표 안은 JS 로 나뉜다 — 함수, 문자열, 일반 이름', () => {
  const line = highlightLines(SOURCE, 'App.vue', LIMIT)[1]

  expect(kindsOf(line, 'cn')?.at(-1)).toBe('function')
  expect(kindsOf(line, "'a'")?.at(-1)).toBe('string')
  // 일반 이름(props)은 JS 구역 안의 색 없는 글자다. 색은 안쪽부터 찾으므로,
  // 언어 구역 표시가 속성 값(문자열 색) 표시보다 안쪽에 있어야 문자열 색을 물려받지 않는다.
  const props = kindsOf(line, 'props') ?? []
  expect(props.includes('language-javascript')).toBe(true)
  expect(props.lastIndexOf('language-javascript') > props.lastIndexOf('attr-value')).toBe(true)
})

test('vue: 바인딩이 아닌 속성(title)의 값은 그대로 문자열이다', () => {
  const line = highlightLines(SOURCE, 'App.vue', LIMIT)[1]

  expect(kindsOf(line, 'plain')?.at(-1)).toBe('attr-value')
})

test('vue: {{ }} 안의 식도 JS 로 나뉜다', () => {
  const line = highlightLines(SOURCE, 'App.vue', LIMIT)[1]

  expect(kindsOf(line, '1')?.at(-1)).toBe('number')
  expect(kindsOf(line, '+')?.at(-1)).toBe('operator')
})

test('html 파일에서는 같은 줄이 바인딩으로 해석되지 않는다', () => {
  const line = highlightLines(SOURCE, 'index.html', LIMIT)[1]

  expect(line?.some(token => token.kinds.includes('language-javascript'))).toBe(false)
})
