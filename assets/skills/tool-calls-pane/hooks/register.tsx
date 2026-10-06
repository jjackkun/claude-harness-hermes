import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { ToolCall } from '../types'
import { registerBand } from './band'
import { ALL_PANES, PANE, TITLE } from './constants'

const COMMAND = 'tool-calls'
// 한 세션에서 보관할 호출 수 상한. 패널은 화면 높이만큼만 그리므로 그보다 넉넉하면 된다.
const MAX_KEPT_CALLS = 200
// 머리줄 1 + 빈 줄 1 + 패널 테두리 여유 2
const RESERVED_ROWS = 4
const FALLBACK_ROWS = 24

const calls = atom({ plugin: 'tool-calls-pane', key: 'calls' } as const, [])

export const register: Register = on => {
  registerBand(on)

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: '이번 세션의 도구 호출을 패널로 보인다',
    })
    void $.ui.open({ id: PANE, title: TITLE })

    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE })

    return { text: '도구 호출 패널을 열었습니다.' }
  })

  on('tool.call', async ($, e, next) => {
    const call: ToolCall = { id: e.tool_use_id, tool: e.tool, isDone: false }
    await update($, calls, list => [...list, call].slice(-MAX_KEPT_CALLS))
    const ran = await next(e)
    await update($, calls, list =>
      list.map(one => (one.id === call.id ? { ...one, isDone: true } : one)),
    )

    return ran
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = await read($, calls)
    const room = Math.max(1, (e.viewport?.rows ?? FALLBACK_ROWS) - RESERVED_ROWS)
    const running = list.filter(call => !call.isDone).length

    return (
      <Box flexDirection="column">
        <Box justifyContent="space-between">
          <Text bold>{`전체 ${list.length}건 · 실행 중 ${running}건`}</Text>
          <Box gap={1}>
            <Button key="close" label="닫기" role="dismiss" onPress={() => $.ui.close({ id: PANE })} />
            {/* 하나가 거절돼도 나머지는 닫는다. */}
            <Button key="close-all" label="전체 닫기" onPress={() => Promise.allSettled(ALL_PANES.map(id => $.ui.close({ id })))} />
          </Box>
        </Box>
        {list.length === 0 && <Text dimColor>아직 도구 호출이 없습니다.</Text>}
        {list.slice(-room).map(call => (
          <Text dimColor={call.isDone}>{`${call.isDone ? '완료' : '실행'} ${call.tool}`}</Text>
        ))}
      </Box>
    )
  })
}
