import type { ClientModule } from 'claude-code'

import { fit } from './cells'
import { BAR_COLUMNS, INDENT } from './constants'
import { paintBar } from './paint'

// color: 줄 색(테마 색 이름). 색이 없으면 null — 값이 없는 칸을 undefined 로 넘기면 엔진이 그리지 못한다.
export type TreeRow = { label: string; depth: number; isDim: boolean; color: string | null }
// rows: 지금 보이는 줄들 · top: 그 첫 줄이 전체에서 몇 번째인지 · bar: 세로 막대(없으면 null)
type Props = { rows: TreeRow[]; top: number; bar: boolean[] | null; columns: number }
// at: 마우스가 올라가 있거나 방향키로 고른 줄(보이는 줄 기준). 없으면 -1.
type State = { at: number }

// 트리. 엔진 버튼 대신 마우스 누름을 직접 받는다: 빠르게 눌러도 글자가 선택되지 않는다.
const TreeView: ClientModule<Props, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const at = surface.state?.at ?? -1
  const last = props.rows.length - 1
  const move = (next: number): void => {
    if (next !== at) {
      surface.setState({ at: next })
    }
  }
  // 누른 줄을 전체 기준 번호로 알린다.
  const choose = (index: number): void => surface.post({ row: props.top + index })
  surface.onPointer(e => {
    if (e.type === 'leave' || e.y < 0 || e.y > last) {
      move(-1)
    } else {
      if (e.type === 'down') {
        choose(e.y)
      }
      move(e.y)
    }
  })
  surface.onKey(key => {
    if (key.key === 'up') {
      move(Math.max(0, at - 1))
    } else if (key.key === 'down') {
      move(Math.min(last, at + 1))
    } else if (key.key === 'return' && at >= 0) {
      choose(at)
    }
  })
  const room = props.columns - BAR_COLUMNS

  return (
    <Box flexDirection="row">
      <Box flexDirection="column" width={room} flexShrink={0}>
        {props.rows.length === 0 && <Text dimColor>항목이 없습니다.</Text>}
        {props.rows.map((row, index) => {
          const text = ' '.repeat(row.depth * INDENT) + row.label
          const shown = text.slice(0, fit(text, room))

          if (index === at) {
            return <Text inverse>{shown}</Text>
          }

          return row.color === null ? (
            <Text dimColor={row.isDim}>{shown}</Text>
          ) : (
            <Text color={row.color} dimColor={row.isDim}>
              {shown}
            </Text>
          )
        })}
      </Box>
      {paintBar(surface.elements, props.bar)}
    </Box>
  )
}

export default TreeView
