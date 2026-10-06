import type { Elements } from 'claude-code'

import type { Model } from '../types'
import { BAR_COLUMNS, GIT_LIST_KEY, GUTTER, MAX_EDIT_CHARS } from './constants'
import { colorOf, labelOf } from './git'
import { highlightLines } from './highlight'
import { paintBar, paintLines } from './paint'
import { divider } from './sidebar'
import type { Side } from './sidebar'
import { barOf, clampTop } from './view'

type Ui = Elements['terminal']

// git 탭의 몸통: 왼쪽에 바뀐 파일 목록, 오른쪽에 고른 파일의 변경 내용. 읽기 전용이다.
export const gitBody = (ui: Ui, model: Model, room: { rows: number; columns: number }, side: Side) => {
  const { Box, Client, Text } = ui
  const { git } = model
  if (git === null) {
    return <Text dimColor>git 상태가 없습니다. 새로고침을 누르십시오.</Text>
  }
  const listTop = clampTop(git.listTop, git.files.length, room.rows)
  const rows = git.files.slice(listTop, listTop + room.rows).map(file => ({
    label: labelOf(file, side.width - BAR_COLUMNS),
    depth: 0,
    // 고른 파일이 있으면 나머지를 흐리게
    isDim: git.path !== null && file.path !== git.path,
    color: colorOf(file),
  }))
  const list = { rows, top: listTop, bar: barOf(listTop, room.rows, git.files.length, room.rows), columns: side.width }
  // 변경 내용은 diff 문법으로 칠한다: 추가된 줄과 지워진 줄에 색이 들어간다.
  const lines = highlightLines(git.diff, 'changes.diff', MAX_EDIT_CHARS)
  const top = clampTop(git.top, lines.length, room.rows)
  const view = { from: top, count: room.rows, left: 0, room: room.columns - GUTTER - BAR_COLUMNS }

  return (
    <Box flexDirection="row">
      <Client key={GIT_LIST_KEY} module="./treeview.tsx" props={list} width={side.width} height={room.rows} />
      {divider(ui, side, room.rows)}
      {git.path === null ? (
        <Text dimColor>{git.files.length === 0 ? '바뀐 파일이 없습니다.' : '왼쪽에서 바뀐 파일을 누르십시오.'}</Text>
      ) : (
        <Box flexDirection="row">
          <Box flexDirection="column" width={room.columns - BAR_COLUMNS} flexShrink={0}>
            {paintLines(ui, lines, view, null)}
          </Box>
          {paintBar(ui, barOf(top, room.rows, lines.length, room.rows))}
        </Box>
      )}
    </Box>
  )
}
