import type { Model } from '../types'
import { BAR_COLUMNS, DIVIDER_COLUMNS, GUTTER, HBAR_ROWS, HEADER_ROWS, MIN_TEXT_COLUMNS, MIN_TREE_COLUMNS } from './constants'
import { visibleRows } from './tree'
import type { Row } from './tree'
import { clampTop, windowOf } from './view'
import type { Window } from './view'

export type Layout = {
  // 머리 세 줄을 뺀 몸통의 높이(행)와 오른쪽 보기 영역의 폭(칸)
  room: { rows: number; columns: number }
  // 읽기 화면에 보일 파일의 창(열린 파일이 없으면 null)
  win: Window | null
  // 트리의 전체 줄과 맨 위에 보이는 줄
  tree: { rows: readonly Row[]; top: number }
  // 트리 칸의 폭과, 세로선을 끌어 갈 수 있는 가장 좁은 폭·가장 넓은 폭
  side: { width: number; min: number; max: number }
}

// 패널 몸통의 크기에서 각 영역의 치수를 계산한다.
export const layoutOf = (state: Model, bodyRows: number, bodyColumns: number): Layout => {
  const rows = Math.max(1, bodyRows - HEADER_ROWS)
  // 트리가 갈 수 있는 가장 넓은 폭: 보기 화면에 줄 번호 칸, 세로 막대, 글자 자리를 남긴다.
  const max = Math.max(MIN_TREE_COLUMNS, bodyColumns - DIVIDER_COLUMNS - GUTTER - BAR_COLUMNS - MIN_TEXT_COLUMNS)
  // 패널이 좁아져도 트리가 보기 화면을 밀어내지 않게 지금 폭을 한계 안에 둔다.
  const width = Math.max(MIN_TREE_COLUMNS, Math.min(state.treeColumns, max))
  // 보기 영역 폭: 패널 폭에서 트리와 세로선을 뺀 나머지.
  const columns = Math.max(GUTTER + 1, bodyColumns - width - DIVIDER_COLUMNS)
  // 읽기 화면은 가로 막대 한 행을 뺀 높이에, 줄 번호와 세로 막대를 뺀 폭으로 본다.
  const win =
    state.open === null ? null : windowOf(state.open, Math.max(1, rows - HBAR_ROWS), columns - GUTTER - BAR_COLUMNS)
  const treeRows = visibleRows(state)

  const tree = { rows: treeRows, top: clampTop(state.treeTop, treeRows.length, rows) }

  return { room: { rows, columns }, win, tree, side: { width, min: MIN_TREE_COLUMNS, max } }
}
