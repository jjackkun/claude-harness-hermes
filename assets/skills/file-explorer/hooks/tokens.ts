import { fit } from './cells'
import type { Token } from './highlight'

// isCursor: 이 조각(한 글자)에 커서가 놓여 있다.
export type Segment = Token & { isCursor?: true }

// 조각들에서 [start, start + count) 글자 범위만 남긴다.
export const clip = (tokens: readonly Token[], start: number, count: number): Token[] => {
  const out: Token[] = []
  let passed = 0
  for (const token of tokens) {
    const from = Math.max(start - passed, 0)
    const to = Math.min(start + count - passed, token.text.length)
    if (to > from) {
      out.push({ ...token, text: token.text.slice(from, to) })
    }
    passed += token.text.length
  }

  return out
}

// 글자 자리 at 의 한 글자를 커서 조각으로 떼어 낸다. 줄 끝이면 빈 칸 커서를 덧붙인다.
export const withCursor = (tokens: readonly Token[], at: number): Segment[] => {
  let passed = 0
  let isPlaced = false
  const out = tokens.flatMap((token): Segment[] => {
    const local = at - passed
    passed += token.text.length
    if (isPlaced || local < 0 || local >= token.text.length) {
      return [token]
    }
    isPlaced = true
    const parts: Segment[] = [
      { ...token, text: token.text.slice(0, local) },
      { ...token, text: token.text.slice(local, local + 1), isCursor: true },
      { ...token, text: token.text.slice(local + 1) },
    ]

    return parts.filter(part => part.text !== '')
  })

  return isPlaced ? out : [...out, { text: ' ', kinds: [], isCursor: true }]
}

// 한 줄에서 화면에 보일 조각: left 글자를 건너뛴 뒤 room 칸에 들어가는 만큼.
export const visibleOf = (line: readonly Token[], left: number, room: number): Token[] => {
  const text = line.map(token => token.text).join('')

  return clip(line, left, fit(text.slice(left), room))
}
