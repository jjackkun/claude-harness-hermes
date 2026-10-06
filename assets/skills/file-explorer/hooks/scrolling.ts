import { HBAR_ROWS, MIN_TREE_COLUMNS, WHEEL_COLUMNS } from './constants'
import type { Change } from './reducers'
import { visibleRows } from './tree'
import { clampTop, linesOf } from './view'

// 휠을 굴릴 때 마우스가 있던 곳
export type Region = 'tree' | 'file' | 'hbar'

const clamp = (value: number, low: number, high: number): number => Math.max(low, Math.min(value, high))

// 휠(또는 스크롤 키)이 by 줄만큼 움직였다. rows: 머리줄을 뺀 몸통 높이.
//  - 트리 위에서: 트리를 넘긴다.
//  - 편집 화면: 누적값만 더한다. 맨 윗줄은 에디터가 들고 있어서, 에디터가 이 값의 차이만큼 옮긴다.
//  - 읽기 화면의 가로 막대 위에서: 좌우로 옮긴다. 가장 긴 줄의 마지막 글자까지만.
//  - 읽기 화면의 그 밖: 파일의 맨 윗줄을 옮긴다(가로 막대 한 행을 뺀 높이 기준).
export const wheeled =
  (by: number, rows: number, region: Region): Change =>
  m => {
    if (m.tab === 'git') {
      // git 탭: 목록 위에서는 목록을, 그 밖에서는 변경 내용을 넘긴다.
      if (m.git === null) {
        return {}
      }
      const isList = region === 'tree'
      const total = isList ? m.git.files.length : m.git.diff.split('\n').length
      const key = isList ? 'listTop' : 'top'

      return { git: { ...m.git, [key]: clampTop(m.git[key] + by, total, rows) } }
    }
    if (region === 'tree') {
      return { treeTop: clampTop(m.treeTop + by, visibleRows(m).length, rows) }
    }
    if (m.open === null) {
      return {}
    }
    if (m.open.isEditing) {
      return { open: { ...m.open, wheel: m.open.wheel + by } }
    }
    const lines = linesOf(m.open.source)
    if (region === 'hbar') {
      const longest = Math.max(0, ...lines.map(line => line.length))

      return { open: { ...m.open, left: clamp(m.open.left + by * WHEEL_COLUMNS, 0, Math.max(0, longest - 1)) } }
    }

    return { open: { ...m.open, top: clampTop(m.open.top + by, lines.length, Math.max(1, rows - HBAR_ROWS)) } }
  }

// 읽기 화면을 왼쪽에서 left 글자 건너뛴 자리로 옮긴다.
export const shiftedTo =
  (left: number): Change =>
  m => (m.open === null ? {} : { open: { ...m.open, left: Math.max(0, left) } })

// 휠이 있던 칸이 어느 곳인지. 가로 막대는 몸통 맨 아래 행, 트리 오른쪽에 있다. 칸을 모르면(스크롤 키) 파일.
export const regionOf = (pointer: { column: number; row: number } | undefined, bodyRows: number, treeColumns: number): Region => {
  if (pointer === undefined) {
    return 'file'
  }
  if (pointer.column < treeColumns) {
    return 'tree'
  }

  return pointer.row === bodyRows - 1 ? 'hbar' : 'file'
}

// 트리 칸의 폭을 바꾼다. 넓은 쪽 한계는 패널 폭에 달려 있어 세로선(화면 모듈)이 이미 맞춰 보낸다.
export const resizedTree =
  (width: number): Change =>
  () => ({ treeColumns: Math.max(MIN_TREE_COLUMNS, Math.round(width)) })
