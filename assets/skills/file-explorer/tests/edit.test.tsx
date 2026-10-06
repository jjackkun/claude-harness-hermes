import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const PLUGIN = 'file-explorer'
const GUTTER = 6
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
type Write = { path: string; text: string }
type Drawn = Awaited<ReturnType<Engine['ui']['mount']>>

// 에디터가 그린 글자 조각들(줄 번호 포함)과, 커서가 놓인 조각의 글자.
const editorTexts = async (ui: Drawn): Promise<string[]> =>
  (await ui.findAll({ type: 'Text', in: 'editor' })).map(one => one.text ?? '')
const cursorText = async (ui: Drawn): Promise<string | undefined> =>
  (await ui.findAll({ type: 'Text', in: 'editor' })).find(one => one.props?.inverse === true)?.text

// 엔진 자리: 파일 하나(a.md)가 있는 폴더. 쓰기는 writes 에 모은다.
const standIn = (on: On, source: string, writes: Write[]): void => {
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('fs.list', async () => ({ value: [{ name: 'a.md', kind: 'file', size: 0, mtimeMs: 0 }] }))
  on('fs.read', async () => ({ value: source }))
  on('fs.write', async (_$, e) => {
    writes.push({ path: e.path, text: e.text })

    return { value: null }
  })
}

// 버튼으로 패널을 열고, a.md 를 눌러 연 뒤, 편집을 켠다.
const openEditor = async ($: Engine) => {
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'open-files' })
  await band.unmount()
  const ui = await $.ui.mount(PANE)
  await ui.pointer({ type: 'down', x: 2, y: 0, in: 'tree' })
  await ui.press({ key: 'mode' })

  return ui
}

test('편집을 켜면 영역 크기를 아직 모르는 첫 그리기에서도 파일 내용과 줄 번호가 보인다', async ($, on) => {
  // Arrange
  standIn(on, 'ab\ncd\n', [])

  // Act
  const ui = await openEditor($)

  // Assert
  // 첫 줄: 줄 번호, 커서(a), 나머지 b · 둘째 줄: 줄 번호와 내용 통째 · 셋째 줄: 파일 끝의 빈 줄
  expect(await editorTexts(ui)).toEqual(['    1 ', 'a', 'b', '    2 ', 'cd', '    3 '])
  expect(await cursorText(ui)).toBe('a')
  await ui.unmount()
})

test('글자를 치면 저장 안 됨이 뜨고, 저장하면 고친 내용이 그 파일에 쓰인다', async ($, on) => {
  // Arrange
  const writes: Write[] = []
  standIn(on, 'ab\ncd\n', writes)
  const ui = await openEditor($)
  expect(await ui.find({ type: 'Text', text: '● 저장 안 됨' })).toBeUndefined()

  // Act
  await ui.key({ key: 'x', in: 'editor' })

  // Assert
  expect(await ui.find({ type: 'Text', text: '● 저장 안 됨' })).toBeDefined()
  await ui.press({ key: 'save' })
  expect(writes.length).toBe(1)
  expect(writes[0]?.path.endsWith('/a.md')).toBe(true)
  expect(writes[0]?.text).toBe('xab\ncd\n')
  expect(await ui.find({ type: 'Text', text: '● 저장 안 됨' })).toBeUndefined()
  await ui.unmount()
})

test('누른 자리에 커서가 놓이고, 줄바꿈은 줄을 나누고 지우기는 다시 합친다', async ($, on) => {
  // Arrange
  const writes: Write[] = []
  standIn(on, 'ab\ncd\n', writes)
  const ui = await openEditor($)

  // Act · Assert — 첫 줄의 a 와 b 사이를 누르고 줄바꿈
  await ui.pointer({ type: 'down', x: GUTTER + 1, y: 0, in: 'editor' })
  await ui.key({ key: 'return', in: 'editor' })
  await ui.press({ key: 'save' })
  expect(writes.at(-1)?.text).toBe('a\nb\ncd\n')

  await ui.key({ key: 'backspace', in: 'editor' })
  await ui.press({ key: 'save' })
  expect(writes.at(-1)?.text).toBe('ab\ncd\n')
  await ui.unmount()
})

test('되돌리기는 마지막으로 읽은 내용으로 돌아가고, 에디터도 그 내용에서 다시 시작한다', async ($, on) => {
  // Arrange
  const writes: Write[] = []
  standIn(on, 'ab\ncd\n', writes)
  const ui = await openEditor($)
  await ui.key({ key: 'x', in: 'editor' })

  // Act
  await ui.press({ key: 'revert' })

  // Assert
  expect(await ui.find({ type: 'Text', text: '● 저장 안 됨' })).toBeUndefined()
  await ui.key({ key: 'y', in: 'editor' })
  await ui.press({ key: 'save' })
  expect(writes.at(-1)?.text).toBe('yab\ncd\n')
  await ui.unmount()
})

test('한도보다 큰 파일은 편집을 켜지 않고 이유를 알린다', async ($, on) => {
  // Arrange — 한도 90000자를 1자 넘는 파일
  standIn(on, 'a'.repeat(90001), [])

  // Act
  const ui = await openEditor($)

  // Assert
  expect(await ui.find({ type: 'Text', text: '파일이 커서 편집할 수 없습니다' })).toBeDefined()
  expect(await ui.find({ type: 'Button', text: '편집' })).toBeDefined()
  await ui.unmount()
})

// 한글은 한 글자가 두 칸이다. 패널 폭 118 → 보기 85칸 → 줄 번호 6칸, 세로 막대 1칸, 커서 1칸을 빼면 글자 자리 77칸 = 한글 38자.
const HANGUL_60 = '가'.repeat(60)

test('두 칸짜리 글자가 많은 줄도 영역 폭 안에서 잘려 다음 행으로 접히지 않는다', async ($, on) => {
  // Arrange
  standIn(on, `ab\n${HANGUL_60}\ncd\n`, [])

  // Act
  const ui = await openEditor($)

  // Assert — 둘째 줄은 38자까지만, 셋째 줄(cd)은 가려지지 않고 그대로
  const texts = await editorTexts(ui)
  expect(texts).toContain('가'.repeat(38))
  expect(texts.some(text => text.includes('가'.repeat(39)))).toBe(false)
  expect(texts).toContain('cd')
  await ui.unmount()
})

test('두 칸짜리 글자 줄에서 누른 화면 칸이 글자 자리로 옮겨진다', async ($, on) => {
  // Arrange
  const writes: Write[] = []
  standIn(on, `ab\n${HANGUL_60}\ncd\n`, writes)
  const ui = await openEditor($)

  // Act — 둘째 줄의 다섯째 칸(= 셋째 글자의 앞 칸)을 누르고 x 를 친다
  await ui.pointer({ type: 'down', x: GUTTER + 4, y: 1, in: 'editor' })
  await ui.key({ key: 'x', in: 'editor' })
  await ui.press({ key: 'save' })

  // Assert
  expect(writes.at(-1)?.text).toBe(`ab\n가가x${'가'.repeat(58)}\ncd\n`)
  await ui.unmount()
})

test('긴 줄의 끝으로 가면 화면이 따라가 줄 끝과 방금 친 글자가 보인다', async ($, on) => {
  // Arrange
  const writes: Write[] = []
  standIn(on, `ab\n${HANGUL_60}\ncd\n`, writes)
  const ui = await openEditor($)

  // Act
  await ui.pointer({ type: 'down', x: GUTTER, y: 1, in: 'editor' })
  await ui.key({ key: 'end', in: 'editor' })
  await ui.key({ key: 'z', in: 'editor' })

  // Assert — 커서 바로 앞 조각이 z 로 끝난다
  const texts = await editorTexts(ui)
  expect(texts.some(text => text.endsWith('가z'))).toBe(true)
  expect(await cursorText(ui)).toBe(' ')
  await ui.press({ key: 'save' })
  expect(writes.at(-1)?.text).toBe(`ab\n${HANGUL_60}z\ncd\n`)
  await ui.unmount()
})
