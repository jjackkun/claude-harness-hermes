import { expect, test } from 'claude-code/testing'

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

test('끝난 도구 호출이 완료 줄로 쌓인다', async ($, on) => {
  // Arrange
  on('tool.call', async () => ({ result: { ok: true }, text: 'ok' }))

  // Act
  await $.tool.call({ tool: 'Read', file_path: 'a.md' })
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...PANE })

  // Assert
  expect(await ui.find({ type: 'Text', text: '전체 1건 · 실행 중 0건' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '완료 Read' })).toBeDefined()
  await ui.unmount()
})

test('실행 중인 도구 호출은 실행 줄로 보인다', async ($, on) => {
  // Arrange
  let finish: () => void = () => {}
  const gate = new Promise<void>(resolve => {
    finish = resolve
  })
  let markReached: () => void = () => {}
  const reached = new Promise<void>(resolve => {
    markReached = resolve
  })
  on('tool.call', async () => {
    markReached()
    await gate

    return { result: { ok: true }, text: 'ok' }
  })

  // Act
  const pending = $.tool.call({ tool: 'Read', file_path: 'a.md' })
  await reached
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...PANE })

  // Assert
  expect(await ui.find({ type: 'Text', text: '전체 1건 · 실행 중 1건' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '실행 Read' })).toBeDefined()
  finish()
  await pending
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
