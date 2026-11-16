import { expect, test } from 'claude-code/testing'

import { applyRow, MAX_KEPT_CALLS } from '../hooks/calls'
import type { AppendedRow } from '../hooks/calls'

const PLUGIN = 'tool-calls-pane'
const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const
const PANE = {
  component: 'Pane',
  requestId: PLUGIN,
  props: {
    title: '도구 호출',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

test('호출이 없으면 빈 안내를 보인다', async $ => {
  for (const surface of SURFACES) {
    // Arrange · Act
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...PANE })

    // Assert
    expect(await ui.find({ type: 'Text', text: '전체 0건 · 실행 중 0건' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '아직 도구 호출이 없습니다.' })).toBeDefined()
    await ui.unmount()
  }
})

const ROW = (door: 'response' | 'tool-result', content: unknown[]) =>
  ({ door, message: { type: door === 'response' ? 'assistant' : 'user', content }, origin: { kind: 'model' }, uuid: `u-${door}` }) as unknown as AppendedRow

test('모델이 부른 도구는 실행, 결과가 오면 완료가 된다', () => {
  // Arrange
  const started = applyRow([], ROW('response', [{ type: 'text', text: '읽습니다' }, { type: 'tool_use', id: 't1', name: 'Read', input: {} }]))

  // Act
  const done = applyRow(started, ROW('tool-result', [{ type: 'tool_result', tool_use_id: 't1', content: 'ok' }]))

  // Assert
  expect(started).toEqual([{ id: 't1', tool: 'Read', isDone: false }])
  expect(done).toEqual([{ id: 't1', tool: 'Read', isDone: true }])
})

test('도구가 없는 줄은 목록을 바꾸지 않는다', () => {
  const list = [{ id: 't1', tool: 'Read', isDone: false }]
  expect(applyRow(list, ROW('response', [{ type: 'text', text: '끝' }]))).toEqual(list)
  expect(applyRow(list, ROW('tool-result', [{ type: 'tool_result', tool_use_id: 'other' }]))).toEqual(list)
})

test(`보관 상한 ${MAX_KEPT_CALLS}건을 넘으면 오래된 것부터 버린다`, () => {
  const full = Array.from({ length: MAX_KEPT_CALLS }, (_, i) => ({ id: `o${i}`, tool: 'Bash', isDone: true }))
  const next = applyRow(full, ROW('response', [{ type: 'tool_use', id: 'new', name: 'Edit' }]))
  expect(next.length).toBe(MAX_KEPT_CALLS)
  expect(next[next.length - 1]).toEqual({ id: 'new', tool: 'Edit', isDone: false })
  expect(next[0]?.id).toBe('o1')
})

test('도구 호출 훅(tool.call)을 걸지 않는다 — Code Mode 가 꺼지지 않게', async ($, on) => {
  // Arrange: 시험의 tool.call 이 불리면 플러그인이 그 위에서 tool.call 을 듣는 것이다
  const seen: string[] = []
  on('tool.call', async (_$, e) => {
    seen.push(e.tool)

    return { result: { ok: true }, text: 'ok' }
  })

  // Act
  await $.tool.call({ tool: 'Read', file_path: 'a.md' })
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...PANE })

  // Assert: 도구는 그대로 돌고, 패널은 tool.call 로 줄을 만들지 않는다
  expect(seen).toEqual(['Read'])
  expect(await ui.find({ type: 'Text', text: '전체 0건 · 실행 중 0건' })).toBeDefined()
  await ui.unmount()
})

test('닫기는 도구 호출 패널만, 전체 닫기는 세 패널을 모두 닫으려 한다', async ($, on) => {
  const ids: string[] = []
  on('ui.close', async (_$, e) => {
    ids.push(e.id)

    return { value: null }
  })
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...PANE })

  await ui.press({ key: 'close' })
  expect(ids).toEqual(['tool-calls-pane'])

  await ui.press({ key: 'close-all' })
  expect(ids.slice(1).sort()).toEqual(['file-explorer', 'hermes-roster-pane', 'tool-calls-pane'])
  await ui.unmount()
})
