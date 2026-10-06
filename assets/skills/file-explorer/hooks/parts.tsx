import type { Elements } from 'claude-code'

import type { Model } from '../types'
import { BAR_COLUMNS, EDITOR_KEY, GUTTER, HBAR_KEY, HBAR_ROWS, MAX_EDIT_CHARS, TREE_KEY } from './constants'
import { treeColorOf } from './git'
import { gitBody } from './gitview'
import { header } from './header'
import type { Actions } from './header'
import { highlightLines } from './highlight'
import { paintBar, paintLines } from './paint'
import { divider } from './sidebar'
import type { Side } from './sidebar'
import { labelOf } from './tree'
import type { Row } from './tree'
import { barOf } from './view'
import type { Window } from './view'

type Ui = Elements['terminal']
// 머리줄 아래 몸통의 높이(행)와 오른쪽 보기 영역의 폭(칸)
export type Room = { rows: number; columns: number }
// 트리의 전체 줄과 맨 위에 보이는 줄
export type Tree = { rows: readonly Row[]; top: number }
// 트리는 화면 모듈이 그린다(마우스 누름을 직접 받는다). 여기서는 보일 줄만 골라 넘긴다.
const tree = ({ Client }: Ui, { rows, top }: Tree, model: Model, width: number, height: number) => {
  const changed = model.git?.files ?? []
  const shown = rows.slice(top, top + height).map(row => {
    // git 상태 색. 색이 붙은 줄은 흐리게 하지 않는다.
    const color = treeColorOf(row.path, row.kind, changed)
    const isDim = color === null && row.kind === 'file' && row.path !== model.open?.path

    return { label: labelOf(row), depth: row.depth, isDim, color }
  })
  const props = { rows: shown, top, bar: barOf(top, height, rows.length, height), columns: width }

  return <Client key={TREE_KEY} module="./treeview.tsx" props={props} width={width} height={height} />
}

const viewer = (ui: Ui, model: Model, win: Window | null, room: Room) => {
  const { Box, Client, Text } = ui
  const { open } = model
  if (open === null || win === null) {
    return <Text dimColor>왼쪽에서 파일을 누르십시오.</Text>
  }
  if (open.isEditing) {
    const props = { source: open.source, path: open.path, revision: open.revision, wheel: open.wheel, ...room }

    return <Client key={EDITOR_KEY} module="./editor.tsx" props={props} width={room.columns} height={room.rows} />
  }
  // 글자 자리: 줄 번호 칸과 세로 막대를 뺀 나머지. 맨 아래 한 행은 가로 막대 자리로 비워 둔다.
  const text = room.columns - GUTTER - BAR_COLUMNS
  const view = { from: win.startLine - 1, count: win.lines.length, left: open.left, room: text }
  const lines = highlightLines(open.source, open.path, MAX_EDIT_CHARS)
  const hbar = { left: open.left, shown: text, widest: win.widest, columns: room.columns }

  return (
    <Box flexDirection="column">
      <Box flexDirection="row" height={room.rows - HBAR_ROWS}>
        <Box flexDirection="column" width={room.columns - BAR_COLUMNS} flexShrink={0}>
          {paintLines(ui, lines, view, null)}
        </Box>
        {paintBar(ui, barOf(view.from, view.count, win.total, view.count))}
      </Box>
      {(win.isCut || open.left > 0) && (
        <Client key={HBAR_KEY} module="./hbar.tsx" props={hbar} width={room.columns} height={HBAR_ROWS} />
      )}
    </Box>
  )
}

// 패널 한 장: 머리 세 줄과, 탭에 따른 몸통(editor: 트리와 보기·에디터, git: 바뀐 파일과 변경 내용).
export const frame = (ui: Ui, model: Model, win: Window | null, treeRows: Tree, room: Room, side: Side, actions: Actions) => (
  <ui.Box flexDirection="column">
    {header(ui, model, win, actions)}
    {model.tab === 'git' ? (
      gitBody(ui, model, room, side)
    ) : (
      <ui.Box flexDirection="row">
        {tree(ui, treeRows, model, side.width, room.rows)}
        {divider(ui, side, room.rows)}
        <ui.Box flexDirection="column" flexGrow={1}>
          {viewer(ui, model, win, room)}
        </ui.Box>
      </ui.Box>
    )}
  </ui.Box>
)
