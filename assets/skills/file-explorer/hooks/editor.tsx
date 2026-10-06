import type { ClientModule } from 'claude-code'

import { colAt, followLeft } from './cells'
import { BAR_COLUMNS, GUTTER, MAX_EDIT_CHARS } from './constants'
import { follow, place, press } from './editing'
import type { Buffer } from './editing'
import { highlightLines } from './highlight'
import { paintBar, paintLines } from './paint'
import { barOf, clampTop } from './view'

// rows·columns 는 패널 훅이 아는 크기다. 영역이 배치되기 전(surface 크기 0)의 첫 그리기에 쓴다.
// wheel: 이 편집이 시작된 뒤 휠이 움직인 줄 수의 누적(훅이 더하고, 편집을 켜거나 내용을 새로 받을 때 0 으로 되돌린다).
type Props = { source: string; path: string; revision: number; wheel: number; rows: number; columns: number }
// top: 맨 윗줄 · left: 긴 줄을 볼 때 왼쪽에서 건너뛴 글자 수 · seenWheel: top 에 이미 반영한 누적 휠
type State = Buffer & { top: number; left: number; seenWheel: number; revision: number }

// 파일 전체를 들고 있다가, 고칠 때마다 전체 내용을 훅 모듈로 보낸다(한 프레임의 post 는 마지막 것만 전달된다).
const Editor: ClientModule<Props, State> = (props, surface) => {
  const rows = surface.rows > 0 ? surface.rows : props.rows
  const columns = surface.columns > 0 ? surface.columns : props.columns
  // 글자 자리: 줄 번호 칸, 세로 막대, 줄 끝에 놓이는 커서 한 칸을 뺀 나머지
  const room = Math.max(1, columns - GUTTER - BAR_COLUMNS - 1)
  const held = surface.state
  const state: State =
    held !== undefined && held.revision === props.revision
      ? { ...held, left: held.left ?? 0, seenWheel: held.seenWheel ?? 0 }
      : { lines: props.source.split('\n'), row: 0, col: 0, top: 0, left: 0, seenWheel: 0, revision: props.revision }
  // 아직 반영하지 않은 휠만큼 옮긴 맨 윗줄. 그리는 동안에는 상태를 바꾸지 않고 계산만 한다.
  const top = clampTop(state.top + props.wheel - state.seenWheel, state.lines.length, rows)
  const commit = (next: Buffer): void => {
    const left = followLeft(next.lines[next.row] ?? '', state.left, next.col, room)
    surface.setState({ ...next, top: follow(top, next.row, rows), left, seenWheel: props.wheel, revision: state.revision })
    if (next.lines !== state.lines) {
      surface.post({ source: next.lines.join('\n') })
    }
  }
  surface.onKey(key => {
    const next = press(state, key)
    if (next !== null) {
      commit(next)
    }
  })
  surface.onPointer(e => {
    if (e.type === 'down') {
      const row = top + e.y
      const visible = (state.lines[row] ?? '').slice(state.left)
      commit(place(state, row, state.left + colAt(visible, e.x - GUTTER)))
    }
  })
  const { Box } = surface.elements
  const lines = highlightLines(state.lines.join('\n'), props.path, MAX_EDIT_CHARS)

  return (
    <Box flexDirection="row">
      <Box flexDirection="column" width={columns - BAR_COLUMNS} flexShrink={0}>
        {paintLines(surface.elements, lines, { from: top, count: rows, left: state.left, room }, state)}
      </Box>
      {paintBar(surface.elements, barOf(top, rows, state.lines.length, rows))}
    </Box>
  )
}

export default Editor
