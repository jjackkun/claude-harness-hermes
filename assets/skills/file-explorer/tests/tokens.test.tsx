import { expect, test } from 'claude-code/testing'

import { highlightLines } from '../hooks/highlight'
import type { Token } from '../hooks/highlight'
import { grammarOf } from '../hooks/languages'
import { clip, visibleOf, withCursor } from '../hooks/tokens'

const LIMIT = 90000
// 한 줄의 조각을 [가장 안쪽 종류, 글자] 로. 색 없는 글자는 'plain'.
const kinds = (line: readonly Token[] = []) => line.map(token => [token.kinds.at(-1) ?? 'plain', token.text])
const plain = (text: string): Token => ({ text, kinds: [] })

test('파일 이름으로 문법을 고르고, 모르는 파일은 색 없이 둔다', () => {
  expect(grammarOf('docs/a.md')).toBe('markdown')
  expect(grammarOf('scripts/hermes-agent.py')).toBe('python')
  expect(grammarOf('hooks/register.tsx')).toBe('tsx')
  expect(grammarOf('src/App.vue')).toBe('vue')
  expect(grammarOf('deploy/Dockerfile')).toBe('docker')
  expect(grammarOf('Makefile')).toBe(null)
})

test('파이썬: 예약어, 함수 이름, 문자열, 숫자, 주석을 가른다', () => {
  const [line] = highlightLines('def f(): return "a#b" + 12  # 끝', 'x.py', LIMIT)

  expect(kinds(line)).toEqual([
    ['keyword', 'def'],
    ['plain', ' '],
    ['function', 'f'],
    ['punctuation', '('],
    ['punctuation', ')'],
    ['punctuation', ':'],
    ['plain', ' '],
    ['keyword', 'return'],
    ['plain', ' '],
    ['string', '"a#b"'],
    ['plain', ' '],
    ['operator', '+'],
    ['plain', ' '],
    ['number', '12'],
    ['plain', '  '],
    ['comment', '# 끝'],
  ])
})

test('여러 줄에 걸친 문자열은 둘째 줄도 문자열로 본다', () => {
  const lines = highlightLines('x = """첫\n둘"""\ny = 1\n', 'x.py', LIMIT)

  expect(lines.length).toBe(4)
  expect(lines[1]?.every(token => token.kinds.includes('string'))).toBe(true)
  expect(kinds(lines[2])).toEqual([
    ['plain', 'y '],
    ['operator', '='],
    ['plain', ' '],
    ['number', '1'],
  ])
})

test('vue 파일: <script> 안은 JS 로, <style> 안은 CSS 로 나눈다', () => {
  const source = '<template>\n  <p class="a">x</p>\n</template>\n<script>\nconst n = 1\n</script>\n<style>\n.a { color: red; }\n</style>\n'
  const lines = highlightLines(source, 'App.vue', LIMIT)

  // 문장부호와 공백(태그 안의 공백은 태그 조각으로 온다)은 빼고 본다
  expect(kinds(lines[1]).filter(([kind, text]) => kind !== 'punctuation' && text?.trim() !== '')).toEqual([
    ['tag', 'p'],
    ['attr-name', 'class'],
    ['attr-value', 'a'],
    ['plain', 'x'],
    ['tag', 'p'],
  ])
  expect(kinds(lines[4])[0]).toEqual(['keyword', 'const'])
  expect(kinds(lines[7])).toContainEqual(['selector', '.a'])
  expect(kinds(lines[7])).toContainEqual(['property', 'color'])
})

test('마크다운: 제목 줄과 인라인 코드', () => {
  const lines = highlightLines('## 1. 발단\n\na `b` c\n', 'a.md', LIMIT)

  expect(lines[0]?.some(token => token.kinds.includes('title') && token.text.includes('발단'))).toBe(true)
  expect(lines[2]?.some(token => token.kinds.includes('code-snippet') && token.text.includes('b'))).toBe(true)
})

test('한도를 넘는 파일과 모르는 종류의 파일은 색 없이 줄만 나눈다', () => {
  expect(highlightLines('def f(): pass\nx\n', 'x.py', 5)).toEqual([[plain('def f(): pass')], [plain('x')], []])
  expect(highlightLines('def f(): pass\n', 'Makefile', LIMIT)).toEqual([[plain('def f(): pass')], []])
})

test('탭은 한 칸으로 바뀌어 글자 수가 유지된다', () => {
  expect(highlightLines('a\tb', 'Makefile', LIMIT)).toEqual([[plain('a b')]])
})

test('조각을 글자 범위로 자르면 걸친 조각은 잘린 채 종류를 유지한다', () => {
  const tokens: Token[] = [plain('ab '), { text: '"cd"', kinds: ['string'] }, plain(' ef')]

  expect(clip(tokens, 2, 4)).toEqual([plain(' '), { text: '"cd', kinds: ['string'] }])
})

test('커서는 그 자리의 한 글자를 떼어 내고, 줄 끝에서는 빈 칸으로 놓인다', () => {
  expect(withCursor([plain('ab')], 1)).toEqual([plain('a'), { text: 'b', kinds: [], isCursor: true }])
  expect(withCursor([plain('ab')], 2)).toEqual([plain('ab'), { text: ' ', kinds: [], isCursor: true }])
  expect(withCursor([], 0)).toEqual([{ text: ' ', kinds: [], isCursor: true }])
})

test('보일 조각은 칸 수에 맞춰 잘린다 — 두 칸짜리 글자 포함', () => {
  expect(visibleOf([{ text: '# 가나다라', kinds: ['comment'] }], 0, 6)).toEqual([{ text: '# 가나', kinds: ['comment'] }])
})
