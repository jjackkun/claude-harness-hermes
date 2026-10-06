import type { ClientModule } from 'claude-code'

// width: 지금 트리 폭 · min, max: 끌어서 갈 수 있는 가장 좁은 폭과 가장 넓은 폭 · rows: 첫 그리기에 쓸 높이
type Props = { width: number; min: number; max: number; rows: number }
type State = { isDragging: boolean }

// 트리와 보기 화면 사이의 세로선. 누른 채 좌우로 끌면 트리 폭이 바뀐다.
// 영역 안에서 누르면 뗄 때까지 영역 밖의 움직임도 받는다. x 는 세로선 기준이라, 지금 폭에 더하면 새 폭이다.
const Divider: ClientModule<Props, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const isDragging = surface.state?.isDragging ?? false
  const resize = (width: number): void => {
    const kept = Math.max(props.min, Math.min(props.max, width))
    if (kept !== props.width) {
      surface.post({ width: kept })
    }
  }
  surface.onPointer(e => {
    if (e.type === 'down') {
      surface.setState({ isDragging: true })
    } else if (e.type === 'up') {
      surface.setState({ isDragging: false })
    } else if (e.type === 'move' && isDragging) {
      resize(props.width + e.x)
    }
  })
  // 세로선을 누른 뒤에는 좌우 방향키로도 한 칸씩 옮긴다.
  surface.onKey(key => {
    if (key.key === 'left') {
      resize(props.width - 1)
    } else if (key.key === 'right') {
      resize(props.width + 1)
    }
  })
  const rows = surface.rows > 0 ? surface.rows : props.rows

  return (
    <Box flexDirection="column">
      {Array.from({ length: rows }, () => (
        <Text dimColor={!isDragging}>│</Text>
      ))}
    </Box>
  )
}

export default Divider
