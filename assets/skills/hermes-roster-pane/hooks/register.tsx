import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { RosterView } from '../types'
import { agentUseIds, finishesAgent } from './agent-rows'
import { registerBand } from './band'
import { ALL_PANES, COMMAND, PANE, REFRESH_KEY, ROSTER_ARGV, TITLE } from './constants'
import { paneColumns, toFailedView, toView } from './roster'

// 패널이 그리는 명부. 상태 참조는 엔진 규칙상 쓰는 파일 안에 직접 적는다.
const view = atom({ plugin: 'hermes-roster-pane', key: 'view' } as const, null)

const refresh = async ($: EngineInterface): Promise<RosterView> => {
  const loaded = await $.process.run(ROSTER_ARGV).then(toView, toFailedView)
  await update($, view, () => loaded)

  return loaded
}

const open = ($: EngineInterface, loaded: RosterView) =>
  $.ui.open({ id: PANE, title: TITLE, columns: paneColumns(loaded.lines) })

export const register: Register = on => {
  registerBand(on)

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: '헤르메스 에이전트 명부를 패널로 보인다',
    })
    // 띠 버튼을 그릴지 정하려고 읽기만 한다. 패널은 사람이 열 때만 연다.
    await refresh($)

    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    const loaded = await refresh($)
    await open($, loaded)

    return {
      text: loaded.isOk
        ? '에이전트 명부 패널을 열었습니다.'
        : '명부를 읽지 못했습니다. 패널에 오류를 보였습니다.',
    }
  })

  // 에이전트를 부르면 "최근 불린 때" 가 바뀌므로 그 결과 줄이 쌓인 뒤 다시 읽는다.
  // 보기만 한다: 대화 줄을 읽고 그대로 넘긴다. tool.call 을 쓰면 Code Mode 가 꺼진다.
  // 다시 불러오면(reload) 기억이 비지만, 그때는 그 호출 하나의 새로고침만 빠진다.
  const pendingAgents = new Set<string>()
  on('session.append', { door: 'response' }, async ($, e, next) => {
    const kept = await next(e)
    for (const id of agentUseIds(e)) pendingAgents.add(id)

    return kept
  })
  on('session.append', { door: 'tool-result' }, async ($, e, next) => {
    const kept = await next(e)
    const finished = finishesAgent(e, pendingAgents)
    if (finished.length === 0) return kept
    for (const id of finished) pendingAgents.delete(id)
    await refresh($).catch(err => $.ui.status(`명부 새로고침 실패: ${String(err)}`))

    return kept
  })

  on('ui.render', { component: 'Pane', requestId: 'hermes-roster-pane' }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const loaded = await read($, view)

    return (
      <Box flexDirection="column">
        <Box justifyContent="space-between">
          <Button
            key={REFRESH_KEY}
            label="새로고침"
            hotkey="r"
            onPress={async () => {
              await refresh($)
            }}
          />
          <Box gap={1}>
            <Button key="close" label="닫기" role="dismiss" onPress={() => $.ui.close({ id: PANE })} />
            {/* 하나가 거절돼도 나머지는 닫는다. */}
            <Button key="close-all" label="전체 닫기" onPress={() => Promise.allSettled(ALL_PANES.map(id => $.ui.close({ id })))} />
          </Box>
        </Box>
        {loaded === null && <Text dimColor>명부를 아직 불러오지 않았습니다.</Text>}
        {loaded !== null && !loaded.isOk && <Text bold>명부를 읽지 못했습니다.</Text>}
        {loaded?.lines.map(line => <Text>{line === '' ? ' ' : line}</Text>)}
      </Box>
    )
  })
}
