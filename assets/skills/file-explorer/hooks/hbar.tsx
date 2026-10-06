import type { ClientModule } from 'claude-code'

import { barOf } from './view'

// left: 왼쪽에서 건너뛴 글자 수 · shown: 한 줄에 보이는 글자 자리 · widest: 가장 긴 줄의 글자 수
type Props = { left: number; shown: number; widest: number; columns: number }

// 가로 스크롤 막대: `<` 손잡이 `>`. 손잡이 왼쪽·오른쪽(또는 양 끝 화살표)을 누르면 절반 폭씩 넘긴다.
const HBar: ClientModule<Props> = (props, surface) => {
  const { Box, Text } = surface.elements
  // 양 끝 화살표 두 칸을 뺀 나머지가 막대
  const cells = Math.max(1, props.columns - 2)
  const total = Math.max(props.widest, props.left + props.shown)
  const flags = barOf(props.left, props.shown, total, cells) ?? Array.from({ length: cells }, () => true)
  const start = flags.indexOf(true)
  const end = flags.lastIndexOf(true)
  const farthest = Math.max(0, props.widest - props.shown)
  // 한 번에 보이는 폭의 절반: 넘긴 뒤에도 앞 내용의 절반이 남는다.
  const step = Math.max(1, Math.floor(props.shown / 2))
  const go = (direction: -1 | 1): void => {
    const left = Math.max(0, Math.min(farthest, props.left + direction * step))
    if (left !== props.left) {
      surface.post({ left })
    }
  }
  surface.onPointer(e => {
    if (e.type === 'down') {
      const cell = e.x - 1
      if (cell < start) {
        go(-1)
      } else if (cell > end) {
        go(1)
      }
    }
  })
  surface.onKey(key => {
    if (key.key === 'left') {
      go(-1)
    } else if (key.key === 'right') {
      go(1)
    }
  })

  return (
    <Box>
      <Text dimColor={props.left === 0}>{'<'}</Text>
      {start > 0 && <Text dimColor>{'─'.repeat(start)}</Text>}
      <Text>{'━'.repeat(end - start + 1)}</Text>
      {end < cells - 1 && <Text dimColor>{'─'.repeat(cells - 1 - end)}</Text>}
      <Text dimColor={props.left >= farthest}>{'>'}</Text>
    </Box>
  )
}

export default HBar
