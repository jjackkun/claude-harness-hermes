import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { registerBand } from './band'
import { applyRow } from './calls'
import { ALL_PANES, PANE, TITLE } from './constants'

const COMMAND = 'tool-calls'
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

    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE })

    return { text: '도구 호출 패널을 열었습니다.' }
  })

  // 보기만 한다: 대화에 쌓인 줄을 읽고 그대로 넘긴다. tool.call 을 쓰면 Code Mode 가 꺼진다.
  for (const door of ['response', 'tool-result'] as const) {
    on('session.append', { door }, async ($, e, next) => {
      const kept = await next(e)
      // 패널 갱신이 실패해도 대화 줄은 이미 저장됐다 — 오류를 삼키지 않고 상태줄에 알린다
      if (!e.agentId) await update($, calls, list => applyRow(list, e)).catch(err => $.ui.status(`도구 호출 패널 갱신 실패: ${String(err)}`))

      return kept
    })
  }

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
