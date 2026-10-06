import type { OpenFile } from '../types'
import { cellsOf } from './cells'

// isCut: 보이는 줄 가운데 오른쪽이 잘린 줄이 있다 · widest: 보이는 줄 가운데 가장 긴 줄의 글자 수
export type Window = { lines: string[]; startLine: number; total: number; isCut: boolean; widest: number }

export const linesOf = (source: string): string[] => {
  const lines = source.split('\n')

  // 파일 끝 줄바꿈이 만든 빈 마지막 줄은 줄로 세지 않는다.
  return lines.length > 1 && lines.at(-1) === '' ? lines.slice(0, -1) : lines
}

export const clampTop = (top: number, total: number, rows: number): number =>
  Math.max(0, Math.min(top, total - rows))

// 열린 파일에서 화면 높이(rows)만큼만 잘라 낸다. room: 한 줄에 들어가는 글자 자리(칸).
export const windowOf = (open: OpenFile, rows: number, room: number): Window => {
  const lines = linesOf(open.source)
  const top = clampTop(open.top, lines.length, rows)
  const shown = lines.slice(top, top + rows)

  return {
    lines: shown,
    startLine: top + 1,
    total: lines.length,
    isCut: shown.some(line => cellsOf(line.slice(open.left)) > room),
    widest: Math.max(0, ...shown.map(line => line.length)),
  }
}

// 스크롤 막대: cells 칸 가운데 손잡이가 놓일 칸을 true 로. 전부 보이면(total <= shown) null.
// 손잡이 길이는 보이는 비율만큼(최소 한 칸), 위치는 건너뛴 비율만큼.
export const barOf = (offset: number, shown: number, total: number, cells: number): boolean[] | null => {
  if (total <= shown || cells <= 0) {
    return null
  }
  const length = Math.max(1, Math.round((cells * shown) / total))
  const start = Math.min(cells - length, Math.round((offset * cells) / total))

  return Array.from({ length: cells }, (_, index) => index >= start && index < start + length)
}
