import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const PLUGIN = 'file-explorer'
const BODY_ROWS = 13
const PANE = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'Pane',
  requestId: PLUGIN,
  props: {
    title: '파일',
    isFocused: false,
    bodyColumns: 118,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: BODY_ROWS },
    view: {},
  },
} as const
const BAND = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 80 },
} as const
const TWENTY_LINES = Array.from({ length: 20 }, (_, i) => `L${i + 1}`).join('\n') + '\n'
const FILES = Array.from({ length: 15 }, (_, i) => ({ name: `f${String(i).padStart(2, '0')}.md`, kind: 'file', size: 0, mtimeMs: 0 }))

// 엔진 자리: 파일 15개가 있는 폭더, 어느 파일이든 20줄.
const standIn = (on: On, read: string[] = []): void => {
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('fs.list', async () => ({ value: FILES }))
  on('fs.read', async (_$, e) => {
    read.push(e.path)

    return { value: TWENTY_LINES }
  })
}

const openFirstFile = async ($: Engine) => {
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'open-files' })
  await band.unmount()
  const ui = await $.ui.mount(PANE)
  await ui.pointer({ type: 'down', x: 2, y: 0, in: 'tree' })

  return ui
}

// 사람이 휠을 굴린 것처럼: (column, row) 칸 위에서 by 줄. row 를 안 주면 몸통 가운데.
const wheel = ($: Engine, by: number, column: number, row = 5) =>
  $.ui.scroll({
    component: 'Pane',
    requestId: PLUGIN,
    offset: by,
    by,
    bodyRows: BODY_ROWS,
    contentRows: BODY_ROWS,
    origin: { kind: 'person' },
    pointer: { column, row },
  })

test('파일 위에서 휠을 굴리면 그만큼 아래 줄이 보인다', async ($, on) => {
  standIn(on)
  const ui = await openFirstFile($)
  expect(await ui.find({ type: 'Text', text: /^L1$/ })).toBeDefined()

  await wheel($, 3, 60)

  // 9줄이 보인다: L4 ~ L12
  expect(await ui.find({ type: 'Text', text: /^L3$/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^L4$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^L12$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^L13$/ })).toBeUndefined()
  await ui.unmount()
})

test('트리 위에서 휠을 굴리면 트리만 넘어가고 파일은 그대로다', async ($, on) => {
  standIn(on)
  const ui = await openFirstFile($)

  await wheel($, 2, 5)

  // 트리는 10줄이 보인다: f02 ~ f11
  const names = (await ui.findAll({ type: 'Text', in: 'tree' })).map(one => one.text?.trim())
  expect(names.filter(name => name?.endsWith('.md'))).toEqual(FILES.slice(2, 12).map(file => file.name))
  expect(await ui.find({ type: 'Text', text: /^L1$/ })).toBeDefined()
  await ui.unmount()
})

test('넘긴 트리에서 줄을 누르면 화면에 보이는 그 줄의 파일이 열린다', async ($, on) => {
  const read: string[] = []
  standIn(on, read)
  const ui = await openFirstFile($)
  await wheel($, 2, 5)

  // 보이는 첫 줄은 f02
  await ui.pointer({ type: 'down', x: 2, y: 0, in: 'tree' })

  expect(read.at(-1)?.endsWith('/f02.md')).toBe(true)
  await ui.unmount()
})

test('편집 화면에서 휠을 굴리면 에디터의 줄이 넘어가고, 커서는 제자리에 있다', async ($, on) => {
  standIn(on)
  const ui = await openFirstFile($)
  await ui.press({ key: 'mode' })

  await wheel($, 4, 60)

  // 에디터는 10줄이 보인다: 5 ~ 14번 줄. 커서(1번 줄)는 화면 밖이라 반전된 글자가 없다.
  const texts = (await ui.findAll({ type: 'Text', in: 'editor' })).map(one => one.text)
  expect(texts).toContain('    5 ')
  expect(texts).toContain('   14 ')
  expect(texts.includes('    4 ')).toBe(false)
  expect((await ui.findAll({ type: 'Text', in: 'editor' })).some(one => one.props?.inverse === true)).toBe(false)
  await ui.unmount()
})

test('가로 막대(몸통 맨 아래 행) 위에서 휠을 굴리면 읽기 화면이 좌우로 넘어간다', async ($, on) => {
  // Arrange — 어느 파일이든 첫 줄이 길다
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('fs.list', async () => ({ value: FILES }))
  on('fs.read', async () => ({ value: `${'0123456789'.repeat(12)}\nshort\n` }))
  const ui = await openFirstFile($)
  expect(await ui.find({ type: 'Text', text: /^0123456789/ })).toBeDefined()

  // Act — 휠 두 칸(8자)
  await wheel($, 2, 60, BODY_ROWS - 1)

  // Assert
  expect(await ui.find({ type: 'Text', text: /^8901234567/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^short$/ })).toBeUndefined()
  await ui.unmount()
})
