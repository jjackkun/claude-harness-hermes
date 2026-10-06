import type { ProcessRunResult } from 'claude-code'

import type { RosterView } from '../types'
import { HANGUL_FIRST, HANGUL_LAST } from './constants'

// 명부 명령의 결과를 패널이 그릴 줄로 바꾼다. 실패면 stderr(없으면 stdout)를 담는다.
export const toView = ({ exitCode, stdout, stderr }: ProcessRunResult): RosterView => {
  const isOk = exitCode === 0
  const text = isOk ? stdout : stderr || stdout

  return { isOk, lines: text.trimEnd().split('\n') }
}

// 명령을 시작조차 못 했을 때의 화면.
export const toFailedView = (error: unknown): RosterView => ({
  isOk: false,
  lines: [error instanceof Error ? error.message : String(error)],
})

const cellsOf = (line: string): number =>
  [...line].reduce((sum, char) => {
    const code = char.codePointAt(0) ?? 0

    return sum + (code >= HANGUL_FIRST && code <= HANGUL_LAST ? 2 : 1)
  }, 0)

// 표가 줄바꿈 없이 들어가는 패널 폭(칸). 가장 긴 줄의 화면 폭이다.
export const paneColumns = (lines: readonly string[]): number =>
  Math.max(1, ...lines.map(cellsOf))
