import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { sane } from '../hooks/reducers'
import { resizedTree } from '../hooks/scrolling'
import type { Model } from '../types'

const PLUGIN = 'file-explorer'
const BODY_COLUMNS = 118
const PANE = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'Pane',
  requestId: PLUGIN,
  props: {
    title: '파일',
    isFocused: false,
    bodyColumns: BODY_COLUMNS,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 13 },
    view: {},
  },
} as const
const BAND = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 80 },
} as const
const LONG_NAME = '2026-07-08-hermes-skill-utilization-gap.md'

const standIn = (on: On): void => {
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('fs.list', async () => ({ value: [{ name: LONG_NAME, kind: 'file', size: 0, mtimeMs: 0 }] }))
}
const openPane = async ($: Engine) => {
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'open-files' })
  await band.unmount()

  return $.ui.mount(PANE)
}
type Drawn = Awaited<ReturnType<typeof openPane>>
const treeWidth = async (ui: Drawn) => (await ui.find({ type: 'Client', key: 'tree' }))?.props?.width
// 세로선을 누른 채 가로로 by 칸 끌고 뗀다.
const drag = async (ui: Drawn, by: number) => {
  await ui.pointer({ type: 'down', x: 0, y: 3, in: 'divider' })
  await ui.pointer({ type: 'move', x: by, y: 3, in: 'divider' })
  await ui.pointer({ type: 'up', x: by, y: 3, in: 'divider' })
}
const model = (): Model =>
  sane({ listed: {}, expanded: [], treeTop: 0, open: null, notice: null, tab: 'editor', project: '', git: null } as unknown as Model)

test('트리 폭 계산: 받은 폭을 그대로 놓되 가장 좁은 폭 아래로는 가지 않는다', () => {
  expect(model().treeColumns).toBe(32)
  expect({ ...model(), ...resizedTree(50)(model()) }.treeColumns).toBe(50)
  expect({ ...model(), ...resizedTree(3)(model()) }.treeColumns).toBe(12)
})

test('처음 폭은 32칸이고 긴 파일 이름은 잘린다', async ($, on) => {
  standIn(on)

  const ui = await openPane($)

  expect(await treeWidth(ui)).toBe(32)
  expect((await ui.findAll({ type: 'Text', in: 'tree' })).some(one => one.text?.includes(LONG_NAME))).toBe(false)
  await ui.unmount()
})

test('세로선을 오른쪽으로 끌면 트리가 그만큼 넓어져 긴 파일 이름이 다 보이고, 왼쪽으로 끌면 좁아진다', async ($, on) => {
  standIn(on)
  const ui = await openPane($)

  await drag(ui, 20)
  expect(await treeWidth(ui)).toBe(52)
  expect((await ui.findAll({ type: 'Text', in: 'tree' })).some(one => one.text?.includes(LONG_NAME))).toBe(true)

  await drag(ui, -30)
  expect(await treeWidth(ui)).toBe(22)
  await ui.unmount()
})

test('세로선을 아무리 끌어도 트리는 12칸 아래로, 보기 화면은 19칸 아래로 줄지 않는다', async ($, on) => {
  standIn(on)
  const ui = await openPane($)

  await drag(ui, -99)
  expect(await treeWidth(ui)).toBe(12)

  // 패널 118칸 - 세로선 1칸 - 보기 화면의 최소 19칸(줄 번호 6 + 세로 막대 1 + 글자 12) = 98칸
  await drag(ui, 999)
  expect(await treeWidth(ui)).toBe(98)
  await ui.unmount()
})

test('누르지 않고 세로선 위를 지나가기만 해서는 폭이 바뀌지 않는다', async ($, on) => {
  standIn(on)
  const ui = await openPane($)

  await ui.pointer({ type: 'move', x: 15, y: 3, in: 'divider' })

  expect(await treeWidth(ui)).toBe(32)
  await ui.unmount()
})
