import { registerGrammars } from './grammars'
import { grammarOf } from './languages'
import Prism from './vendor/prism.js'
import type { PrismToken } from './vendor/prism.js'

// 한 조각. kinds: 바깥에서 안쪽 순서의 Prism 종류(별칭 포함). 색 없는 글자는 빈 배열.
export type Token = { text: string; kinds: readonly string[] }

// Prism 의 겹친 결과를 맨 안쪽 글자 조각들로 편다. 종류는 바깥 것을 물려받는다(별칭 먼저, 제 종류가 가장 뒤).
const leavesOf = (token: string | PrismToken, kinds: readonly string[]): Token[] => {
  if (typeof token === 'string') {
    return [{ text: token, kinds }]
  }
  const own = [...kinds, ...[token.alias ?? []].flat(), token.type]

  return [token.content].flat().flatMap(child => leavesOf(child, own))
}

// 줄바꿈에서 끊어 줄별 조각으로 나눈다. 탭은 한 칸으로 바꾼다(커서 자리와 글자 자리를 1:1 로 맞추기 위해).
const toLines = (leaves: readonly Token[]): Token[][] =>
  leaves.reduce<Token[][]>(
    (lines, leaf) => {
      const [first = '', ...rest] = leaf.text.replaceAll('\t', ' ').split('\n')
      const made = (text: string): Token[] => (text === '' ? [] : [{ text, kinds: leaf.kinds }])

      return [...lines.slice(0, -1), [...(lines.at(-1) ?? []), ...made(first)], ...rest.map(made)]
    },
    [[]],
  )

// 같은 내용을 다시 물으면 다시 나누지 않는다(그리기마다 불린다).
let last: { source: string; name: string | null; lines: Token[][] } | null = null

// 파일 전체를 문법에 맞춰 나눈 줄별 조각. 여러 줄에 걸친 문자열·주석도 이어서 본다.
// maxChars 를 넘는 파일과 모르는 종류의 파일은 색 없이 줄만 나눈다.
export const highlightLines = (source: string, path: string, maxChars: number): Token[][] => {
  const name = source.length > maxChars ? null : grammarOf(path)
  if (last !== null && last.source === source && last.name === name) {
    return last.lines
  }
  registerGrammars()
  const grammar = name === null ? undefined : Prism.languages[name]
  const leaves =
    grammar === undefined
      ? [{ text: source, kinds: [] }]
      : Prism.tokenize(source, grammar).flatMap(token => leavesOf(token, []))
  last = { source, name, lines: toLines(leaves) }

  return last.lines
}
